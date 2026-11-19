# ifx ICE: OpenMP map of an array of an extended type with an allocatable component

## Summary

`ifx` aborts with an internal compiler error (#5623, "internal abort") when an
OpenMP construct maps an **array of an extended derived type** whose
**allocatable component is declared in the extension**:

```fortran
type :: base_t
end type base_t

type, extends(base_t) :: ext_t
  real, allocatable :: f(:)
end type ext_t

type(ext_t), allocatable :: buf(:)
...
!$omp target enter data map(to: buf)    ! error #5623
```

This is not specific to the GPU backend: it also crashes **without**
`-fopenmp-targets`, i.e. with plain `-qopenmp`.

## Environment

- Compiler: `ifx (IFX) 2026.1.0 20260617`
- System: Aurora (Intel GPU, `spir64` offload target)

## Reproduce

```bash
./run.sh
```

| Build           | Flags                                        | Result                    |
|-----------------|----------------------------------------------|---------------------------|
| bug_offload     | `-qopenmp -fopenmp-targets=spir64`           | **ICE**, error #5623      |
| bug_host        | `-qopenmp`                                   | **ICE**, error #5623      |
| workaround      | `-qopenmp -fopenmp-targets=spir64 -DWORKAROUND` | compiles (run on a GPU node) |
| workaround_host | `-qopenmp -DWORKAROUND`                      | compiles, prints `PASS`   |

```
reproducer.F90(50): error #5623: **Internal compiler error: internal abort** Please report this error along with the circumstances in which it occurred in a Software Problem Report.  Note: File and line given may not be explicit cause of this error.
```

The ICE occurs at both `-O0` and `-O3`.

## What triggers it and what doesn't

The mapped object is `x`, or `buf` when mapped directly.

| Variant                                                                 | Result  |
|-------------------------------------------------------------------------|---------|
| Array of `ext_t` (allocatable component declared in the extension)      | **ICE** |
| ... as an allocatable array component of a mapped type                  | **ICE** |
| ... as a fixed-size array component, `type(ext_t) :: buf(2)`            | **ICE** |
| Scalar `type(ext_t)` (not an array)                                     | OK      |
| Pointer array component, `type(ext_t), pointer :: buf(:)`               | OK      |
| Allocatable component declared in the **parent** type instead           | OK      |
| Extension with no allocatable component (e.g. `integer :: n`)           | OK      |
| Same type without `extends(...)`                                        | OK      |
| Parent type abstract or concrete                                        | no difference: ICE both ways |

It does not matter which construct does the mapping. All of these crash:
`!$omp target update to(x)`, `!$omp target enter data map(to: x)`,
`!$omp target map(tofrom: x)`, and the implicit map of `x` when an offloaded
`do concurrent` (`-fopenmp-target-do-concurrent`) references a component of it.

## Impact on MOM6

`MOM_control_struct` (`src/core/MOM.F90`) contains `type(diag_ctrl) :: diag` by
value. Through that, it contains an array of this pattern four levels down:

```
MOM_control_struct
  %diag                     type(diag_ctrl)
    %remap_axesTL(:) ...    type(axes_grp), allocatable array
      %piecemeal_3d         type(diag_buffer_3d)
        %buffer(:)          type(buffer_3d), allocatable array;
                            buffer_3d extends buffer_base and adds `field`, an allocatable
```

So any OpenMP construct that maps `CS` in `MOM.F90` crashes. That includes
`!$omp target update to(CS)` in `initialize_MOM`, and every offloaded
`do concurrent` that touches a `CS%...` component, e.g.

```fortran
do concurrent (j=js:je, i=is:ie)
  CS%ssh_rint(i,j) = 0.        ! MOM.F90: error #5623
enddo
```

How it was found: delta debugging (automatically deleting components while the ICE
persists) reduced `MOM_control_struct`'s 140 components to `diag`, then `diag_ctrl`'s
66 components to the `remap_axes*` arrays, then `axes_grp`'s components to
`piecemeal_3d`.

## Workaround

Remove the type extension. In MOM6, `buffer_base` is an empty abstract type that is
never used polymorphically, so under `-DIFX_WORKAROUNDS_MOM6`, `buffer_2d` and
`buffer_3d` in `src/framework/MOM_diag_buffers.F90` no longer extend it. Behavior is
unchanged. With this change `MOM.F90` compiles as it is, including
`!$omp target update to(CS)`.
