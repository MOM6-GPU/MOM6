# 01: OpenMP `private(x)` and `do concurrent local(x)` in one procedure: privatizer symbol clash

**Compiler:** AMD flang 24.0.0git, AFAR drop 24.4.0 (ROCm/llvm-project `af5d6a9790939cc301486abeec5a51ee48f59c18`)
**Severity:** ICE / hard error on valid code. Blocks 10 MOM6 files.
**Needs only:** `-fopenmp` (host, no offload, no optimization).

## Summary
No explicit clause is needed: an implicitly private OpenMP loop index (`!$omp parallel do` over
`do j = ...`) clashes just the same with a `do concurrent ... local(j)` in the same procedure.

If one procedure names the same variable in an OpenMP `private` clause and in a
`do concurrent ... local` specifier, flang emits two privatizer ops with the same symbol name,
`_Q<scope>E<var>_private_<type>`: an `omp.private` and a `fir.local`. They live in the same
module symbol table, so the module is invalid. Which error you get depends on the order of the two
constructs and on `-fdo-concurrent`:

| MRE | flags | result |
|-----|-------|--------|
| `mre_redefinition.f90` (do concurrent first) | `-fopenmp -fdo-concurrent=none` | `error: redefinition of symbol named '_QFsEi_private_i32'` |
| `mre_redefinition.f90` | `-fopenmp -fdo-concurrent=host` (or `device`) | **segfault** in `DoConcurrentConversion::genPrivatizers` |
| `mre_lookup_failure.f90` (omp loop first) | `-fopenmp` | `error: failed to lookup privatizer op with symbol: '@_QMmFsEi_private_i32'` |
| `mre_implicit_loop_index.f90` (no `private` clause: the `parallel do` index is implicitly private) | `-fopenmp` | `error: failed to lookup privatizer op with symbol: '@_QFsEj_private_i32'` |
| `mre_offload.f90` | `-O2 -fopenmp --offload-arch=gfx90a -fdo-concurrent=device` | **segfault** in `genPrivatizers` |
| `mre_redefinition.f90` | no `-fopenmp` | compiles |

`./run.sh` runs all of these.

## MRE
```fortran
subroutine s(a, n)
  integer :: n
  real :: a(n)
  integer :: i, ii
  do concurrent (ii=1:n) local(i)
    i = ii
    a(i) = 0.
  enddo
  !$omp parallel do private(i)
  do ii = 1, n
    i = ii
    a(i) = 1.
  enddo
end subroutine
```
```
$ amdflang -c -fopenmp -fdo-concurrent=none mre_redefinition.f90
error: loc("mre_redefinition.f90":4:14): redefinition of symbol named '_QFsEi_private_i32'
error: verification of lowering to FIR failed

$ amdflang -c -fopenmp -fdo-concurrent=host mre_redefinition.f90
 #3 (anonymous namespace)::DoConcurrentConversion::genPrivatizers(...)
 #4 (anonymous namespace)::DoConcurrentConversion::genParallelOp(...)
 #5 (anonymous namespace)::DoConcurrentConversion::matchAndRewrite(fir::DoConcurrentOp, ...)
flang-24: error: unable to execute command: Segmentation fault (core dumped)
```

## Likely cause
`privatizeSymbol<OpType>` (`flang/lib/Lower/Support/Utils.cpp`) builds the privatizer name from
(variable, type) alone and looks up an existing one with `moduleOp.lookupSymbol<OpType>(name)`.
That lookup is typed, so if a symbol of the *other* kind (`fir.local` vs `omp.private`) already has
that name it is missed, and a second op with the same name is created. The do-concurrent-to-OpenMP
conversion then also derives `<name>.omp` from the `fir.local` and crashes in `genPrivatizers`.

A local fix that worked on an earlier amd-staging snapshot: when the name is taken by an op of the
other kind, add a suffix (`_omp` / `_local`).

## Workaround
- `-mmlir --enable-delayed-privatization=false` on affected files (non-delayed OpenMP
  privatization creates no `omp.private` symbol). Used per file in `ocean_only/afar_workarounds.mk`.
  Caveat: on the non-delayed path a combined `target teams loop ... private(...)` hits
  `not yet implemented: Unhandled clause FIRSTPRIVATE in TARGET construct`
  (`MOM_set_viscosity.F90:818`), so that file can't use the flag.
- Or rename the variable in one of the two constructs. Done in `MOM_interface_heights.F90`
  (`find_rho_bottom_2d`) and `MOM_set_viscosity.F90` (`set_viscous_ML`, `set_viscous_BBL`), guarded by
  `#ifdef AMD_WORKAROUNDS` with the original code in the `#else` branch
  (`grep -rn AMD_WORKAROUNDS src`). `afar_workarounds.mk` defines the macro.

## Hit in MOM6 (dev/gpu)
`MOM_interface_heights.F90` (`find_rho_bottom_2d`: `i`, `j`), `MOM_tracer_advect.F90` (`advect_x`,
`advect_y`: `k`), `MOM_kappa_shear.F90` (`i`, `j`, `nzc`), `MOM_continuity_PPM.F90`
(`zonal/meridional_mass_flux`: `i`, `j`, `l_seg`), `MOM_wave_speed.F90`,
`MOM_lateral_mixing_coeffs.F90`, `MOM_set_diffusivity.F90`, `MOM_set_viscosity.F90`
(`set_viscous_ML`: `i`, `j`), `MOM_mixed_layer_restrat.F90` (`mixedlayer_restrat_Bodner`: `k`, `dh`),
`MOM_tracer_hor_diff.F90`.
