# ifx ICE: offloaded `do concurrent` with multiple bounds from one derived-type object

## Summary

`ifx` crashes with an internal compiler error (segmentation violation in the
spir64 device compile) when a `do concurrent` loop is offloaded with
`-fopenmp-target-do-concurrent` **and** two or more of its index ranges take
their bounds from components of the **same** derived-type object:

```fortran
type(bounds_t), intent(in) :: b
...
do concurrent (j=1:b%m, i=1:b%n)
  a(i,j) = val
end do
```

## Environment

- Compiler: `ifx (IFX) 2026.1.0 20260617`. An ICE in the same MOM6 routine was also seen with 2025.3.2; this reproducer was not tested on that version.
- System: Aurora (Intel GPU, `spir64` offload target)
- Flags: `-qopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent`

## Reproduce

```bash
./run.sh
```

This builds `reproducer.F90` three ways. Run it on a compute node so the offload
binaries can execute on the GPU.

| Build      | Flags                                  | Result                        |
|------------|----------------------------------------|-------------------------------|
| bug        | offload flags above                    | **ICE**, error #5633          |
| workaround | offload flags + `-DWORKAROUND`         | compiles                      |
| host       | `-qopenmp` (no `-fopenmp-targets`)     | compiles, prints `PASS`       |

Or compile it directly:

```bash
ifx -O3 -qopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent reproducer.F90
```

```
/tmp/ifx.../ifx....bc: error #5633: **Internal compiler error: segmentation violation signal raised** Please report this error along with the circumstances in which it occurred in a Software Problem Report.  Note: File and line given may not be explicit cause of this error.
compilation aborted for /tmp/ifx.../ifx....bc (code 3)
```

The ICE occurs at both `-O0` and `-O3`.

## What triggers it and what doesn't

| Variant                                                        | Result    |
|----------------------------------------------------------------|-----------|
| `do concurrent (j=1:b%m, i=1:b%n)`                             | **ICE**   |
| `do concurrent (j=b%jsd:b%jed, i=b%isd:b%ied)`                 | **ICE**   |
| Only one range from `b`: `do concurrent (j=1:m, i=1:b%n)`      | OK        |
| 1-D: `do concurrent (i=b%lo:b%hi)`                             | OK        |
| Two different objects: `do concurrent (j=1:c%n, i=1:b%n)`      | OK        |
| Bounds copied to locals: `n=b%n; m=b%m; do concurrent (j=1:m, i=1:n)` | OK |
| `!$omp target teams loop collapse(2)` with `b%m`, `b%n` bounds | OK        |
| Host only (no `-fopenmp-targets=spir64`)                       | OK        |

None of these change the result: the array being an automatic array, an
assumed-shape dummy, an explicit-shape dummy, or allocatable, and whether there
is an `!$omp target enter data` for it.

## Impact on MOM6

MOM6 commonly writes loops like `do concurrent (j=G%jsd:G%jed, i=G%isd:G%ied)`.
The first ICE hit in the build is in `int_density_dz_wright`
(`src/equation_of_state/MOM_EOS_Wright.F90`):

```fortran
do concurrent (j=HI%jsd:HI%jed, i=HI%isd:HI%ied)
  z0pres(i,j) = 0.0
enddo
```

A grep finds about 28 loops with this pattern in 10 source files, e.g.
`MOM_barotropic.F90`, `MOM_dynamics_split_RK2.F90`, `MOM_set_viscosity.F90` and
`MOM_density_integrals.F90`.

## Workaround

Copy the derived-type bounds into local integers before the loop, or bind them
with an `associate` construct (both compile). Results stay bitwise identical.

In MOM6 this is applied under `-DIFX_WORKAROUNDS_MOM6` with `associate`:

```fortran
#ifdef IFX_WORKAROUNDS_MOM6
  ! Avoid an ifx ICE, see bug_reports/ifx_dc_dtype_bounds_ice
  associate(ifx_jsd=>G%jsd, ifx_jed=>G%jed, ifx_isd=>G%isd, ifx_ied=>G%ied)
  do concurrent (j=ifx_jsd:ifx_jed, i=ifx_isd:ifx_ied)
#else
  do concurrent (j=G%jsd:G%jed, i=G%isd:G%ied)
#endif
    ...
  enddo
#ifdef IFX_WORKAROUNDS_MOM6
  end associate
#endif
```

`grep -rn ifx_dc_dtype_bounds_ice src config_src` lists every site.
