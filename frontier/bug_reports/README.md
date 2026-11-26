# Compiler bug reports: MOM6 (dev/gpu) + FMS on Frontier (MI250X, gfx90a)

Compiler under test: **AMD AFAR drop 24.4.0** (TheRock ROCm 10.3.0), AMD flang 24.0.0git,
ROCm/llvm-project `af5d6a9790939cc301486abeec5a51ee48f59c18`, built 11/11/26.
Install: `mom/therock-afar-24.4.0-multiarch-10.3.0-a71da8f`. Environment: `source ../afar_env.sh`.

MOM6 flags: `-g -O2 -fopenmp --offload-arch=gfx90a -fdo-concurrent=device`.

One directory per bug: `README.md` (symptom, MRE, cause, workaround), the MRE source(s), and
`run.sh`, which reproduces it with the AFAR compiler.

| # | Bug | Kind | Blocks MOM6? | Workaround |
|---|-----|------|--------------|------------|
| [01](01-omp-private-vs-do-concurrent-local-name-clash/) | `omp private(x)` + `do concurrent local(x)` in one procedure: privatizer symbol clash (redefinition / failed lookup / segfault in `genPrivatizers`) | ICE / error on valid code | yes, 10 files | `-mmlir --enable-delayed-privatization=false` per file, or rename the index variables |
| [02](02-parallel-diagnostic-printing-heap-corruption/) | flang crashes at random (heap corruption in `fir::RecordType::print`) when diagnostics that print ops are emitted from several MLIR threads at once, e.g. the `loop`->`simd` warning | random ICE on valid code | yes, intermittently (`MOM_continuity_PPM`) | `-mmlir --mlir-disable-threading` |
| [03](03-declare-target-named-constant/) | `declare target to/enter(<parameter>)` is an error, argument form only warns | inconsistency | no | use argument form |
| [04](04-debuginfo-duplicate-arg-nested-reductions/) | `-g` + nested `do concurrent` reductions: "conflicting debug info for argument" | error on valid code | yes, 1 file | `-g0` per file |
| [05](05-do-concurrent-inside-target-region-nested-target/) | `do concurrent` inside an `!$omp target` region becomes a nested `omp.target`: inner loop silently skipped on GPU, fault at -O0, libomp assert in host fallback | **silent wrong code** | yes, 50 loops in 4 files | plain `do` for the inner loop (not yet applied) |
| [06](06-do-concurrent-array-reduction-device/) | `do concurrent reduce(+: array)` on the device: memory fault or garbage | **wrong code** | yes, every global sum (`reproducing_sum`) | `target teams distribute parallel do reduction(...)` in `MOM_coms.F90` |
| [07](07-teams-loop-array-reduction-dominance/) | `target teams loop reduction(+: array)`: "operand #0 does not dominate this use" | error on valid code | no (alternative workaround for 06) | use `distribute parallel do` |

Per-file workarounds for the MOM6 build: `../afar_workarounds.mk`.

## Investigated, not compiler bugs
- **`.mod` files from another flang version are rejected** ("Cannot use module file for module
  'iso_c_binding'"). Expected behavior. Dependencies were rebuilt with AFAR.
- **C-driver link of Fortran offload objects is missing the device Fortran runtime**
  (`_FortranAPointerAssociateScalar` undefined). `amdclang` doesn't add the Fortran runtime (host or
  device). Link with `amdflang`, or pass `-Xoffload-linker -lflang_rt.runtime -lm -lc`. Hit by
  MOM6 configure's `jmp_buf` probe; fixed in `src/MOM6/ac/configure.ac`.
- **`!$omp do` inside `do concurrent`** (MOM6 `MOM_barotropic.F90`) is rejected. Correct: those
  were stray directives in MOM6. Removed.

## Earlier bugs (October amd-staging, `../compiler/`) that AFAR 24.4.0 fixes
`compiler/02` (optional array live-in), `04` (declare both results), `05` (nested reduce of local),
`07` (local_init): all compile now. Runtime checks of 02/07 and the `08` target-update slowdown
still need a GPU node.
