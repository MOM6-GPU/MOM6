# Investigation (not yet reproduced): host structure corrupted after implicit map

**Status: not a confirmed compiler bug.** The simple reproducer here passes on the GPU.
Don't file it until a reproducer fails.

## What happened in MOM6

In the double_gyre run on Aurora (ifx 2026.1.0, `-fopenmp-target-do-concurrent`), the
host crashed with SIGSEGV in the first `step_MOM`:

```
#0 mom_regridding::get_zlike_cs  MOM_regridding.F90:2904   get_zlike_CS = CS%zlike_CS
#1 mom_diag_remap::diag_remap_update  MOM_diag_remap.F90:350
#2 mom_diag_mediator::diag_update_remap_grids
#3 mom::step_mom  MOM.F90:899
```

With `LIBOMPTARGET_DEBUG=1`, the last kernel launched was `step_mom__l819`:

```fortran
do concurrent (j=js:je, i=is:ie)
  CS%ssh_rint(i,j) = 0.
enddo
```

`CS` (`MOM_control_struct`, about 113 KB) was not present on the device at that
point: `extract_surface_state` maps it on entry and releases it on exit. So the
kernel mapped all of `CS` implicitly, `tofrom`. Afterwards, the core file showed
the following on the host:

- **`CS%diag%diag_remap_cs(:)%regrid_cs%zlike_CS` was null.** This pointer component
  sits inside elements of an allocatable array of derived type, nested in `CS`.
- **The target of `CS%tv%eqn_of_state` was zeroed,** including its polymorphic
  `type` pointer, now `0x0`.

## What the reproducer tests (all pass on the GPU, at -O0 and -O3)

`reproducer.F90`: a structure with an allocatable array and a pointer component to
another structure. An offloaded loop writes the array while the structure isn't
present. The cases are:

- (A) `do concurrent`
- (B) `do concurrent` after `enter data map(to:)` + `exit data map(release:)`
- (C) an explicit `!$omp target` loop

The host pointer, its target and the scalar fields all survive.

## Next steps to reproduce

Add the MOM6 shapes the simple cases don't cover:

1. A pointer component inside elements of an allocatable array of derived type that
   is itself a component, i.e. `cs%list(:)%inner%p`.
2. A pointer component to a type that holds a polymorphic `class(...), pointer`, like
   `EOS_type%type`. Map it explicitly with `enter data map(to: cs%tv)` and
   `exit data map(release: cs%tv)` around the implicit map, as `extract_surface_state`
   does.

## MOM6 fix (applies to every compiler)

The five offloaded loops that ran while `CS` wasn't present (3 in `step_MOM`, 2 in
`step_MOM_tracer_dyn`) now refer to the arrays they use through `associate` names,
e.g. `associate(ssh_rint => CS%ssh_rint)`. Those arrays are already mapped at
initialization, so `CS` is no longer mapped at all.

Checked in the device code: before the fix those five kernels took `CS` as an
argument; after it, none outside `extract_surface_state` do. This also removes a
113 KB copy to and from the device on every call. Answers are bitwise identical.
