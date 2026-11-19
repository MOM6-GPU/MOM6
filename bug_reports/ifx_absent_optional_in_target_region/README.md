# ifx: absent optional argument in a target region crashes the host (unconfirmed)

**Status: not reproduced standalone.** On a GPU node, `run.sh` prints `PASS` for both
builds: ifx handles the simple form correctly. In MOM6 the crash went away when `OBC` was
replaced by a local pointer, but the core showed the program counter in the middle of an
instruction (a jump to a garbage address). So the trigger is something more specific to
`zonal_flux_adjust`, such as passing the optional pointer as an actual argument to a
`declare target` procedure (`flux_elem_OBC`) inside the region. Don't file this until a
reproducer fails.

## Summary

If an optional dummy argument is referenced anywhere inside an `!$omp target` region,
ifx makes it implicitly `FIRSTPRIVATE` (or `PRIVATE`), and it warns about this:

```
warning #5590: Optional parameter OBC is being implicitly added as a FIRSTPRIVATE clause.
Optional parameters will fault if not present.
```

When the argument is absent, the host dereferences it while setting up the region and
crashes with SIGSEGV before the kernel launches. This happens even when the code inside
the region only touches the argument behind a test that is false when it is absent.

```fortran
subroutine adjust(x, n, OBC)
  type(obc_t), optional, pointer :: OBC
  use_obc = .false.
  if (present(OBC)) then ; if (associated(OBC)) use_obc = .true. ; endif
  !$omp target map(tofrom: x)
  !$omp loop
  do i=1,n
    x(i) = x(i) + 1.0
    if (use_obc) then ; if (OBC%segnum(i) /= 0) x(i) = 0.0 ; endif   ! never runs if absent
  enddo
  !$omp end target
end subroutine adjust

call adjust(x, 8)   ! OBC absent -> host SIGSEGV
```

OpenMP (5.1 and later) says an absent optional argument in a data-sharing or map clause
is treated as not present, rather than being dereferenced. ifx documents the fault in its
warning, so this may be a known limitation rather than a bug; it's still worth reporting.

## Environment

- Compiler: `ifx (IFX) 2026.1.0 20260617`
- System: Aurora (Intel GPU, `spir64` offload target)

## Reproduce

```bash
./run.sh
```

| Build      | Compile                 | Run on a GPU node   |
|------------|-------------------------|---------------------|
| bug        | warning #5590           | host SIGSEGV        |
| workaround | no warning              | `PASS`              |

The warning shows on any node; the crash needs a GPU node.

## Impact on MOM6

`zonal_flux_adjust` and `meridional_flux_adjust` (`src/core/MOM_continuity_PPM.F90`)
use `OBC` inside their `!$omp target` regions, guarded by `local_open_BC`.
`set_zonal_bt_cont` and `set_merid_bt_cont` call them without `OBC`. The first
`step_MOM` crashed on the host:

```
#0 mom_continuity_ppm::zonal_flux_adjust  MOM_continuity_PPM.F90:1469
#1 mom_continuity_ppm::set_zonal_bt_cont  MOM_continuity_PPM.F90:1587
```

`LIBOMPTARGET_DEBUG=1` showed the routine's local arrays being mapped, and then the crash
before its target region (`zonal_flux_adjust__l1389`) was launched.

The other #5590 sites in the build were checked one by one:

| Site | Status |
|---|---|
| `find_face_areas` `add_max`, `set_dtbt` `gtot_est`, Wright `rho_ref` | Safe: the kernels sit inside `present()` branches |
| `zonal/meridional_mass_flux` `BT_cont` | Safe: inside `if (set_BT_cont)` |
| `CorAdCalc` `Waves` | Safe: inside `if (Stokes_VF)` |
| Wright `dz_neglect` | Safe: always passed together with `intx_dpa` |
| `horizontal_viscosity` `OBC` | Absent only from the unsplit solvers |
| `calc_isoneutral_slopes` `OBC` | Absent only from ML-MEKE features and `meso_sfn_ANN` |

The last two will crash if those code paths are used.

## Workaround

Under `-DIFX_WORKAROUNDS_MOM6`, both routines copy `OBC` into a local pointer before the
region (null if absent) and use it inside:

```fortran
type(ocean_OBC_type), pointer :: OBC_loc
OBC_loc => NULL() ; if (present(OBC)) OBC_loc => OBC
...  ! inside the target region: OBC_loc instead of OBC
```
