# ifx: components mapped after their parent keep stale descriptors on the device

**Status: confirmed.** Wrong results at `-O0` and `-O3` on the GPU, with no error.
`-DWORKAROUND` fixes it.

## Summary

Suppose a derived-type object is sent to the device as a whole while its allocatable
components are still unallocated, and the components are allocated and mapped afterwards:

```fortran
allocate(pv)
!$omp target enter data map(alloc: pv)
!$omp target update to(pv)                 ! components still unallocated
allocate(pv%a(n,n), pv%b(n,n))
!$omp target enter data map(to: pv%a, pv%b)
```

Mapping `pv%a` attaches its device address to the device copy of `pv`, but the rest of the
descriptor (bounds, allocation status) stays as it was when `pv` was sent. So in kernels:
- `allocated(pv%b)` is false, and guarded writes are skipped;
- writes to `pv%a(i,j)` use the stale bounds and land in the wrong elements;
- `!$omp target update from(pv%a)` brings back mostly zeros (a sum of about 1600 instead
  of 87120).

When the components are allocated before the parent is first mapped, everything works
(case 1 in the reproducer).

**Workaround:** after the last component has been allocated and mapped, send the whole
object again with `!$omp target update to(pv)`. That sends the current descriptors, and the
runtime re-attaches the device addresses of the mapped components when a kernel launches.

## Impact on MOM6

MOM6 commonly creates a control structure on the device in its init routine and allocates
its arrays afterwards. Kernel writes through the structure were lost, and reads came from
the wrong memory. Seen in:
- `visc%bbl_thick_u`, `visc%Kv_bbl_u` (`set_viscous_BBL`): no bottom drag;
- the dynamics `CS%PFu` etc.: the baroclinic acceleration was zero;
- `vertvisc_CS%h_u`;
- `BT_cont%FA_u_E0` etc.: the barotropic transport was zero.

The fix (`IFX_WORKAROUNDS_MOM6`) adds `!$omp target update to(<object>)` at the end of:
- `set_visc_init`;
- `initialize_dyn_split_RK2`;
- `VarMix_init`;
- `vertvisc_init`;
- `alloc_BT_cont_type`;
- `initialize_MOM` (for `CS` and `CS%ADp`).

## Environment

- Compiler: `ifx (IFX) 2026.1.0 20260617`
- Flags: `-qopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent`
- System: Aurora (Intel GPU, `spir64` offload target)

## Reproduce

```bash
./run.sh     # needs a GPU node
```

| Build          | Case 1 (allocate, then map) | Case 2 (MOM6 order) |
|----------------|-----------------------------|---------------------|
| bug            | correct                     | `FAIL (4 wrong)`    |
| `-DWORKAROUND` | correct                     | `PASS`              |
