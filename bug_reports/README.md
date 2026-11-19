# Compiler bug reports

Standalone reproducers for compiler bugs hit while porting MOM6 to GPUs. Each
subdirectory has a `README.md`, a runnable `reproducer.F90` and a `run.sh`.

## ifx workarounds in MOM6: `IFX_WORKAROUNDS_MOM6`

Building with `-DIFX_WORKAROUNDS_MOM6` enables source workarounds for ifx bugs,
so compilation can get further and expose the next bug. Each workaround is
guarded like this:

```fortran
#ifdef IFX_WORKAROUNDS_MOM6
  ! Avoid an ifx ICE, see bug_reports/<report_dir>
  <workaround>
#else
  <original code>
#endif
```

Without the macro the code is unchanged. Search for a report's directory name
to find every place its workaround is applied.

## Reports

| Directory | Compiler | Symptom | Workaround sites |
|---|---|---|---|
| [ifx_dc_dtype_bounds_ice](ifx_dc_dtype_bounds_ice/) | ifx 2026.1.0 | ICE #5633 when an offloaded `do concurrent` takes bounds from 2+ components of one derived-type object | 34 loops in 11 files |
| [ifx_map_extended_type_array_ice](ifx_map_extended_type_array_ice/) | ifx 2026.1.0 | ICE #5623 when OpenMP maps an array of an extended type whose allocatable component is in the extension (also host-only) | `MOM_diag_buffers.F90` (2 types) |
| [ifx_declare_target_separate_module_procedure](ifx_declare_target_separate_module_procedure/) | ifx 2026.1.0 | No `declare target` placement works for a separate module procedure: both = error #8682; interface only = body never compiled for the device (GPU load fails); body only = `do concurrent` callers not offloaded | `MOM_intrinsic_functions.F90` (1 directive) |
| [ifx_kernel_args_explicit_shape_bounds](ifx_kernel_args_explicit_shape_bounds/) | ifx 2026.1.0 (PVC) | Kernel arguments exceed the 2048-byte GPU limit: each explicit-shape array costs 5 args (40 B) vs 1 for allocatable; JIT builds only fail at run time | `set_viscous_BBL` (28 work arrays made allocatable) |
| [ifx_update_component_copies_parent](ifx_update_component_copies_parent/) | ifx 2026.1.0 | `target update to/from(CS%x)` with a pointer/allocatable `CS` also transfers the whole of `CS`, overwriting host (or device) state | 49 update directives in 3 files |
| [ifx_implicit_map_struct_pointer_components](ifx_implicit_map_struct_pointer_components/) | ifx 2026.1.0 | **Not reproduced.** Investigation notes for a host-structure corruption, possibly related to `ifx_update_component_copies_parent` (unverified) | (fixed in MOM6 by not mapping `CS` implicitly) |
| [ifx_absent_optional_in_target_region](ifx_absent_optional_in_target_region/) | ifx 2026.1.0 | Absent optional argument referenced in a target region (warning #5590) is dereferenced on the host: SIGSEGV before the kernel launches. **Unconfirmed: simple MRE passes on GPU** | `MOM_continuity_PPM.F90` (2 routines) |
| [ifx_dc_reduce_locality](ifx_dc_reduce_locality/) | ifx 2026.1.0 (PVC) | At -O3 a conditional min reduction (`if (v*r > 1) r = 1/v`) on the GPU returns its initial value, in `do concurrent reduce` and `omp target ... reduction` alike. Suspected fast-math + `huge()` identity overflow | `set_dtbt` in `MOM_barotropic.F90` |
| [ifx_optional_scalar_private](ifx_optional_scalar_private/) | ifx 2026.1.0 | **Not reproduced.** Present optional scalar flagged PRIVATE (#5590) in an offloaded loop; MRE passes on GPU | (harmless local copies in `MOM_barotropic.F90`, `MOM_EOS_Wright.F90`) |
| [ifx_l0_staging_buffer_overrun](ifx_l0_staging_buffer_overrun/) | ifx 2026.1.0 runtime (Level Zero) | One `target update` that submits a large transfer followed by many small ones (structure with allocatable components inside a mapped parent) leaves wrong data on the device (19/20 trials); OK with `LIBOMPTARGET_LEVEL_ZERO_STAGING_BUFFER_SIZE=0` or `COMMAND_MODE=sync` | `barotropic_init`: update through a byte view |
