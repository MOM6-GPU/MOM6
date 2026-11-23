# Intel offload runtime (Level Zero): a construct with more than 64 small host-to-device transfers leaves wrong data on the device

**Status: confirmed on a GPU node** (Aurora, PVC). Wrong in 19 of 20 trials with the
default runtime settings. Always correct with
`LIBOMPTARGET_LEVEL_ZERO_COMMAND_MODE=sync`, with
`LIBOMPTARGET_LEVEL_ZERO_STAGING_BUFFER_SIZE=0`, or with `LIBOMPTARGET_DEBUG=1` (which
slows the host down).

The directory name says "kernel race" because that was the first theory. The kernel is not
involved: the device data is wrong before any kernel runs, and stays wrong.

## Summary

Two things combine.

1. **Runtime (the bug).** In the default asynchronous command mode, a host-to-device
   transfer of up to 16 KiB is first copied into a staging buffer. The measurements below
   fit a ring of **64** staging buffers that is reused without waiting for the transfers
   that are still pending. A small transfer is overwritten if 64 or more further small
   transfers are submitted in the same construct before it runs. The device then receives
   the data of the transfer submitted 64 places later.
2. **What makes one construct submit that many transfers.**
   - ifx turns `!$omp target update to(CS)`, for a structure with allocatable components,
     into one transfer of the whole structure plus one map entry per component (1297
     entries for MOM6's `barotropic_CS`).
   - After every entry that moves data, libomptarget rewrites every pointer that is
     attached anywhere in the enclosing mapped structure ("Restoring target pointer ..."
     in the debug log), with one 8-byte transfer each. This includes the pointers of a
     parent structure when `CS` is a component of a mapped parent.

   So the number of small transfers is about (components) x (attached pointers + 1). The
   transfer of the whole structure at the head of the construct is large and slow, and the
   small ones queue up behind it.

In MOM6 the scalars read back as -5.829E+303. That is the bit pattern of a device address
(`0xff00fffffeXXXXXX`): they received the data of a later pointer-restoring transfer.

## Environment

- Compiler: `ifx (IFX) 2026.1.0 20260617`
- Runtime: libomptarget Level Zero plugin from the same oneAPI release
- System: Aurora (Intel Data Center GPU Max / PVC)

## Reproduce (on a GPU node)

```bash
./run.sh                                   # the variants in the first table below
VARIANTS="ALLOC_UPDATE_MAP:NPAR=22" ./run.sh   # chosen variants; A:B means -DA -DB
```

`reproducer.F90` follows MOM6: a parent structure (like `MOM_dyn_split_RK2_CS`) holds a
child structure by value (like `barotropic_CS`). The child has 60 allocatable components,
288 KB of padding and then the scalars `dtbt_fraction`, `bebt`, `BT_Coriolis_scale` and
`initialized`. Each variant runs 20 trials on newly allocated objects, and reads the three
real scalars back in a kernel. Counts are wrong trials out of 20.

| Variant | Sequence | default | `sync` | staging off |
|---|---|---|---|---|
| full | map the child's 60 components, then `update to(CS)` | **19** | 0 | 0 |
| `-DNO_PARENT` | same, child allocated on its own | **19** | 0 | 0 |
| `-DNO_ALLOCS` | no allocatable components (the update is one entry) | 0 | 0 | 0 |
| `-DNO_PAD` | same as full, small structure | **19** | 0 | 0 |
| `-DWORKAROUND` | full, plus an empty `!$omp target` region after the update | **19** | 0 | 0 |
| `-DSCALAR_UPDATE` | map the components, then update only the 4 scalars | **19** | 0 | 0 |
| `-DUPDATE_FIRST` | `update to(CS)` before any component is mapped | 0 | 0 | 0 |
| `-DALLOC_UPDATE_MAP` | MOM6 order: allocate, `update to(CS)`, then map the child's components | 0 | 0 | 0 |
| `-DALLOC_UPDATE_MAP -DPARENT_ALLOCS` | MOM6 order, parent has 10 mapped allocatable components | 0 | 0 | 0 |
| `-DALLOC_UPDATE_MAP -DPARENT_MANY` | **MOM6's case:** MOM6 order, parent has 60 mapped components | **19** | 0 | 0 |
| `-DALLOC_UPDATE_MAP -DPARENT_MANY -DBYTE_UPDATE` | same, with the workaround | 0 | 0 | 0 |

- **Trial 1 always passes.**
- **Not needed:** the padding (`-DNO_PAD`), or a particular component size (`-DNSIZE=8`,
  `63`, `65` all fail like the default 64).
- **Not a trigger in the MOM6 order:** a nested structure with allocatable components
  (`-DNESTED`), or pointer components to unmapped host objects (`-DPOINTERS`).
- **The large transfer is not affected:** `-DSCAN` also compares the 288 KB padding, and it
  is always intact.

### The threshold

`-DALLOC_UPDATE_MAP -DNPAR=<K>` gives the parent K attached pointers. The update then
submits, after the padding: `dtbt_fraction`, K pointer transfers, `bebt`, K, `scale`, K,
`initialized`, K. Number of wrong trials out of 20, by scalar:

| K | `dtbt_fraction` | `bebt` | `scale` | Transfers after `bebt` (3K+2) | after `scale` (2K+1) |
|---|---|---|---|---|---|
| 10, 15, 18, 20 | 0 | 0 | 0 | at most 62 | at most 41 |
| 22 | 0 | **17** (13 in a second run) | 0 | 68 | 45 |
| 26 | 0 | **19** | 0 | 80 | 53 |
| 31 | **13** | **19** | 0 | 95 | 63 |
| 33 | **13** | **19** | **19** | 101 | 67 |
| 40, 64 | **19** | **19** | **19** | | |

- A scalar goes wrong exactly when 64 or more transfers follow it.
- With K = 31, `dtbt_fraction` read back 1.0, the value of `scale`, which was submitted
  exactly 64 transfers later. `bebt` read back NaN, the bit pattern of `.true.`:
  `initialized` was submitted 64 transfers after `bebt`.
- `dtbt_fraction` is the first small transfer and often runs before it is overwritten.
  This is where the timing dependence comes from.

All variants pass with `-DBYTE_UPDATE`, including `-DNPAR=64` and `-DNPAR=200`.

### What does not reproduce it

The count of 64 is not the whole condition. Two simpler programs pass (0 wrong) with the
default settings, and are not kept here:

- **No derived types:** one `target update to(big, s001, ..., s130)` with a large array
  and 130 separately mapped scalars. 0 of 20 trials wrong, twice.
- **Explicit scalar list:** a small structure with up to 96 attached pointers and
  `update to(C%s1, C%s2, C%s3, C%s4)`. 0 of 5 trials wrong for each pointer count.

So the transfers must also queue up faster than they run, and what makes them do so in
`reproducer.F90` is not identified. The ring of 64 staging buffers is inferred from the
threshold table and the runtime's symbol names (`StagingBufferTy::getNext`,
`L0StagingBufferCount`), not read from its source.

## What the runtime should do

A `target update` without `nowait` must be complete when the construct ends, and the
device data must then equal the host data. The staging buffers must not be reused while a
transfer that reads them is pending.

## Impact on MOM6

`barotropic_init` did `!$omp target update to (CS)` on the 306,944-byte `barotropic_CS`.
At that point 41 pointers were attached in the enclosing `MOM_dyn_split_RK2_CS`. The
debug log shows 1297 map entries and 52,163 small transfers in that one construct. Every
`CS` scalar read by `set_dtbt`'s kernels was a device address, `dtbt` became about 1e19 s,
and the model stopped with:

```
FATAL: btstep: number of barotropic step (nstep+nfilter) is 0
```

It was hidden whenever `LIBOMPTARGET_DEBUG=1` was used to investigate.

## Workaround

**In MOM6 (`IFX_WORKAROUNDS_MOM6`, `barotropic_init` in `src/core/MOM_barotropic.F90`):**
update the structure through a byte array that shares its storage. This is one map entry,
so the construct submits one large transfer plus one small transfer per attached pointer.

```fortran
integer(kind=c_int8_t), pointer :: CS_bytes(:)
call c_f_pointer(c_loc(CS), CS_bytes, [storage_size(CS)/8])   ! CS needs the TARGET attribute
!$omp target update to (CS_bytes)
```

- **Verified in MOM6:** with the default command mode, double_gyre no longer stops in
  `btstep`, and completes 10 model days in 12 min 25 s (about 1.2 min per model day,
  against about 2.5 with `sync`). Energies agree with the `sync` run to 15 digits. The
  last digit varies from run to run in both modes, so this is not a bitwise comparison.
- **It is not a general replacement for `update to(CS)`.** ifx's own update also refreshes
  the data of allocatable components that are already mapped. The byte array transfers
  only the structure itself. In `barotropic_init` no component of `CS` is mapped yet at
  that point (the debug log shows only no-op lookups for them), so the two are equivalent
  there.
- **Runtime alternatives:** `LIBOMPTARGET_LEVEL_ZERO_STAGING_BUFFER_SIZE=0` avoids the bug
  in every variant here. `LIBOMPTARGET_LEVEL_ZERO_COMMAND_MODE=sync` also does, but
  serializes all device operations and is slow.

## Other places in MOM6 with the same pattern

These also submit 64 or more small transfers in one construct (counts from a
`LIBOMPTARGET_DEBUG=1` log of double_gyre). They are not changed. They gave correct
results in the runs so far, but nothing guarantees it.

| Construct | Small transfers | Large transfer first |
|---|---|---|
| `update to(CS)` in `initialize_MOM` (`MOM.F90`), two executions | 7,038 and 38,732 | no |
| `update to(CS)` of a 1,928-byte structure | 1,958 | no |
| `update to(CS)` of a 552-byte structure (pressure force) | 1,334 | no |
| `update to( CS )` in `MOM_lateral_mixing_coeffs.F90` | 192 | 25.6 KB |
| `update to(CS)` in `vertvisc_init` (`MOM_vert_friction.F90`) | 162 | 23.3 KB |
| `update to (CS%dtbt)` in `barotropic_init`, later | 97 (96 attached pointers) | no |
| `enter data` of the MOM control structure | 1,526 | |
| Some kernels with many mapped scalars (`horizontal_viscosity`, `extract_surface_state`) | 67 to 247 | |

The other eight whole-structure updates cannot simply use the byte array: some of them
rely on the update refreshing the data of mapped components (for example `CS%u` and
`CS%v` in `initialize_MOM`).
