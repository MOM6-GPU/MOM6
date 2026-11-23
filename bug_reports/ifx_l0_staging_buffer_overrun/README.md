# Intel offload runtime (Level Zero): staging buffers overrun when one `target update` submits many small transfers

**Status: confirmed on a GPU node** (Aurora, PVC). With the default runtime settings,
`reproducer.F90` reads wrong values on the device in 19 of 20 trials.

## Summary

In the default asynchronous command mode, the Level Zero plugin copies small host-to-device
transfers (≤ 16 KiB) into staging buffers. When one OpenMP construct submits a large
transfer followed by many small ones, a small transfer can receive the data of the transfer
submitted 64 places after it. The device then holds wrong values, with no error. A ring of
64 staging buffers being reused before the pending transfers have run would explain the
measurements.

Fortran code makes this easy to hit. `!$omp target update to(C)`, for a structure `C` with
allocatable components that sits inside a mapped parent:

- **ifx side:** becomes one transfer of `C` plus one map entry per allocatable component of
  `C`.
- **runtime side:** after each entry, libomptarget rewrites every pointer attached in the
  enclosing mapped structure with an 8-byte transfer ("Restoring target pointer ..." in a
  `LIBOMPTARGET_DEBUG` log).

So one directive becomes (components) × (attached pointers) small transfers. In MOM6 that was
52,163 transfers in one directive.

## Reproducer

`reproducer.F90` (about 130 lines):
- a parent structure with 60 mapped allocatable components;
- inside it, a child of about 290 KB with 60 allocatable components (allocated on the host,
  not mapped) and three scalars;
- the scalars are set on the host, `!$omp target update to(child)` is called, and a kernel
  reads them back.

```bash
./run.sh        # on a GPU node
```

| Build | default | `COMMAND_MODE=sync` | `STAGING_BUFFER_SIZE=0` |
|---|---|---|---|
| bug | **19 of 20 wrong** (NaN) | 0 | 0 |
| `-DWORKAROUND` (update through a byte view: one map entry) | 0 | 0 | 0 |
| `-DNO_PAD` (child of about 4.5 KB) | 0 | 0 | 0 |

- The first trial always passes.
- **A large transfer at the head is required.** Without the child's padding, its own
  transfer is staged too and nothing goes wrong.

## Threshold

From `investigation/`, varying the number K of attached pointers in the parent:

| K | Wrong scalars |
|---|---|
| ≤ 20 | none |
| 22–26 | the first scalar only (≥ 64 small transfers follow it) |
| 31 | `bebt` and `dtbt_fraction` read the values submitted exactly 64 transfers later |
| ≥ 40 | all scalars |

Each extra scalar fails once 64 or more small transfers come after it. Without a large
transfer at the head of the construct, nothing fails even with 130 small transfers.

## Environment

- Compiler: `ifx (IFX) 2026.1.0 20260617`
- Runtime: libomptarget Level Zero plugin from the same oneAPI release
- System: Aurora (Intel Data Center GPU Max / PVC)

## Impact on MOM6

`barotropic_init` (`src/core/MOM_barotropic.F90`) does `!$omp target update to (CS)` on
`barotropic_CS`, a component of the mapped `MOM_dyn_split_RK2_CS` (41 attached pointers).
`CS`'s scalars then read as -5.829E+303 on the device: the bit pattern of a device address,
taken from a later pointer-restoring transfer. As a result:

- `dtbt` came out at about 1e19 s;
- the model stopped with `FATAL: btstep: number of barotropic step (nstep+nfilter) is 0`;
- the bug was hidden whenever `LIBOMPTARGET_DEBUG=1` was set, because the log slows the host
  down.

**Other sites:** eight more whole-structure `update to(...)` directives in MOM6 have the same
shape, with up to 38,732 small transfers (`initialize_MOM`). They did not fail in double_gyre
runs.

## Workarounds

- **Runtime:** `export LIBOMPTARGET_LEVEL_ZERO_STAGING_BUFFER_SIZE=0` (fixes every variant),
  or `LIBOMPTARGET_LEVEL_ZERO_COMMAND_MODE=sync` (slow).
- **Code, used in MOM6 under `IFX_WORKAROUNDS_MOM6` in `barotropic_init`:** update the
  structure through a byte view of its storage, which is a single map entry.
  ```fortran
  call c_f_pointer(c_loc(CS), CS_bytes, [storage_size(CS)/8])
  !$omp target update to (CS_bytes)
  ```
  This does not refresh the data of allocatable components that are already mapped. It is
  correct in `barotropic_init` because none are mapped at that point.

With the code workaround, double_gyre runs to day 10 in the default async mode (job
9103608), about twice as fast as with `sync`.

## Investigation

`investigation/` keeps the full variant reproducer (`reproducer_variants.F90`,
`run_variants.sh`, `VARIANTS="A:B" ./run_variants.sh`) and notes (`NOTES.md`). It shows
which ingredients don't matter: the parent/child nesting, nested structures and pointer
components, and component size. It also has the complete threshold sweep. The directory was
first created as `ifx_l0_update_kernel_race`, before the cause was known.
