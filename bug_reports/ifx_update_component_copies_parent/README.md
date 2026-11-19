# ifx: `target update` of a component transfers the whole pointer/allocatable parent

**Status: confirmed on a GPU node.** The bug build prints `host CS%flag = 1` (FAIL); the
`-DWORKAROUND` build prints `7` (PASS).

## Summary

When the base object is a **pointer** (or **allocatable**) to a derived type, ifx
compiles

```fortran
type(cs_t), pointer :: CS
!$omp target update from(CS%arr)
```

as two transfers: the whole of `CS`, plus `CS%arr`. So:

- **`update from(CS%arr)`** overwrites the entire host structure with the device copy.
  Any host-only change since `CS` was mapped is lost, and if the device copy was made
  with `map(alloc:)`, the host structure is filled with uninitialized device memory.
- **`update to(CS%arr)`** overwrites the entire device structure with the host copy,
  including the device's array descriptors.

OpenMP says `target update` transfers only the listed storage, here the data of
`CS%arr`.

## Evidence

The map-type table ifx emits for the update (read from `-S` assembly, no GPU needed):

| Base object / spelling                       | Map types       | Meaning                   |
|----------------------------------------------|-----------------|---------------------------|
| `type(cs_t), pointer :: CS`; `from(CS%arr)`  | `0x2 0x2`       | **whole CS** + arr        |
| `type(cs_t), pointer`; `from(CS%arr(:))`     | `0x2 0x2`       | **whole CS** + arr        |
| `type(cs_t), allocatable, target`            | `0x2 0x2`       | **whole CS** + arr        |
| pointer base; `update to(CS%arr)`            | `0x1 0x1`       | **whole CS** + arr        |
| `type(cs_t), intent(inout) :: CS`            | `0x0 0x2`       | correct (parent: no copy) |
| pointer base via `associate(arr => CS%arr)`  | `0x2`           | correct                   |

`enter data map(to:)` and `exit data map(from:)` on a pointer base also emit a whole-parent
entry. Those only transfer when the parent is newly mapped or its reference count drops to
zero.

With `LIBOMPTARGET_DEBUG=1`, MOM6's `!$omp target update from(CS%diffu, CS%diffv)`
shows:

```
Entry 0: Base=0x...be00, Size=557424, Type=0x2, Name=CS_pointee
Entry 1: ...           , Size=40704,  Type=0x2, Name=DIFFU_data
Entry 2: ...           , Size=40768,  Type=0x2, Name=DIFFV_data
Moving 557424 bytes (tgt:0xff00fffffee00000) -> (hst:0x000015276affbe00)
```

## Environment

- Compiler: `ifx (IFX) 2026.1.0 20260617`
- System: Aurora (Intel GPU, `spir64` offload target)

## Reproduce

```bash
./run.sh
```

Part 1 prints the map-type tables and runs anywhere. Part 2 needs a GPU node: the
program sets a host-only field after mapping `CS`, then does `update from(CS%arr)`.

```
=== bug
map types for update_from: 0x2 0x2
host CS%flag   = 1   (expect 7; 1 means all of CS was copied back)     [GPU node]
=== workaround (-DWORKAROUND)
map types for update_from: 0x2
host CS%flag   = 7                                                       [GPU node]
```

## Impact on MOM6

In `step_MOM_dyn_split_RK2`, `CS` is a pointer to `MOM_dyn_split_RK2_CS`, about 557 KB.
That structure contains `barotropic_CSp` by value, and its device copy was created with
`map(alloc:)` (`MOM.F90`). The first `update from(CS%diffu, CS%diffv)` copied the
uninitialized device structure over the host one. The next call to `btcalc` then failed:

```
FATAL: btcalc: Module MOM_barotropic must be initialized before it is used.
```

A source scan found **49 affected update directives in 3 files**:

| File | Directives | Base |
|---|---|---|
| `MOM_dynamics_split_RK2.F90` | 26 | pointer `CS` |
| `MOM.F90` | 19 | pointers `sfc_state`, `sfc_state_diag` |
| `MOM_tracer_hor_diff.F90` | 4 | pointer `Reg` |

## Workaround

Under `-DIFX_WORKAROUNDS_MOM6`, each affected directive binds the components with
`associate`. An `if(...)` clause becomes a host `if` around the `associate`, because the
selector must be allocated:

```fortran
#ifdef IFX_WORKAROUNDS_MOM6
  associate(ifx_upd1=>CS%diffu, ifx_upd2=>CS%diffv)
  !$omp target update from(ifx_upd1, ifx_upd2)
  end associate
#else
  !$omp target update from(CS%diffu, CS%diffv)
#endif
```
