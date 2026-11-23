# ifx: kernel launch cost grows with the allocatable components of every structure referenced

**Status: confirmed performance issue.** Results are correct. No error or warning is
printed.

## Summary

When a kernel references one component of a derived-type object, ifx implicitly maps the
whole object, including every allocatable component, on every launch. This happens even
when the object and all its components are already present on the device, and the kernel
uses only one of them. Each launch then pays about **0.4 µs per allocatable component**
of host-side runtime work: table lookups, `malloc`/`free`, mutexes and pointer
re-attachment.

```fortran
type :: t100_t
  real, allocatable :: a001(:), a002(:), ..., a100(:)
end type
type(t100_t) :: s
!$omp target enter data map(to: s)      ! s and all 100 components now on the device

do concurrent (i=1:n)                   ! 50 us per launch, against 11 us with 1 component
  s%a001(i) = s%a001(i) + 1.0
enddo
```

On one PVC tile, the same one-array kernel launches in:

| How the kernel reaches `s%a001` | µs per launch | Kernel arguments |
|---|---|---|
| Implicit map, structure with 1 allocatable component | 11.8 | 8 |
| Implicit map, 25 components | 18.2 | 56 |
| Implicit map, 100 components (`do concurrent` or `!$omp target teams loop`) | 50.6 | 206 |
| 100 components, `!$omp target teams loop map(present, tofrom: s%a001)` | 11.2 | 7 |
| 100 components, `s%a001` passed to a routine as an array argument | 10.8 | 7 |

The argument counts are the `with N arguments` that `LIBOMPTARGET_INFO=1` reports for each
launch: each allocatable component adds two entries.

`-fopenmp-do-concurrent-maptype-modifier=present` makes no difference. A default
`declare mapper` that maps only the scalar components did not help either, and gave wrong
results in our test. Pointer components instead of allocatable ones gave about 13 µs.

OpenMP maps the allocatable components of a mapped structure, so the extra map entries
themselves may be expected. The issue is their cost when everything is already present: a
present structure with *N* allocatable components costs *N* full runtime lookups per
launch.

**Request:** make the implicit map of an already-present structure cheap (for example,
skip or batch the per-component work when the parent is present with unchanged
components), or provide an option to map a structure's allocatable components only when the
kernel references them.

## Impact on MOM6

MOM6 kernels routinely read a few arrays from large control structures (`G`, `CS`).
- On Aurora, a 2-day `double_gyre` run averages **333 map entries per kernel launch**.
- Kernels in the barotropic solver average about **1,400**, because they reference both the
  barotropic `CS` and the grid `G`.
- Those launches cost about 0.5 ms each, against microseconds of kernel time.

In that run, kernels took 1.7 s of device time but the model run took 52 s.
- A VTune host profile puts nearly all the CPU time outside the JIT compiler in
  `libomptarget` (present-table lookups, `postProcessingTargetDataEnd`, shadow pointers),
  `malloc`/`free`, mutexes and the Level Zero driver.
- The whole 10-day run takes 262 s on one PVC tile with ifx. The same 10-day run takes about
  30 s on a V100 with nvfortran.

Workaround options, which all need editing many kernels:
- an explicit `!$omp target teams loop map(present, …)` naming only the components used;
- passing the arrays as arguments.

None is applied in MOM6 yet.

## Environment

- Compiler: `ifx (IFX) 2026.1.0 20260617`
- Flags: `-g -O3 -qopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent`
- Runtime: `LIBOMPTARGET_LEVEL_ZERO_STAGING_BUFFER_SIZE=0` (see `../ifx_l0_staging_buffer_overrun`;
  timings are the same without it)
- System: Aurora, one PVC tile (`ZE_AFFINITY_MASK=0`)

## Reproduce

```bash
./run.sh
```

On a GPU compute node, the script:
- builds the reproducer with and without `-fopenmp-do-concurrent-maptype-modifier=present`;
- prints the time per launch of each variant;
- prints the number of arguments the runtime processes for one launch of each kernel
  (`LIBOMPTARGET_INFO=1`).

The reproducer is generated: each structure's component list is written out in full.
Expected output:

```
Implicit map of the structure (current behaviour):
  do concurrent, 1 allocatable component                     11.8 us/launch
  do concurrent, 25 allocatable components                   18.2 us/launch
  do concurrent, 100 allocatable components                  50.6 us/launch
  target teams loop, 100 allocatable components              50.6 us/launch
Same kernel, 100 components, without the implicit map of the structure:
  target teams loop map(present, tofrom: s%a001)             11.2 us/launch
  do concurrent on s%a001 passed as an argument              10.8 us/launch
results: PASS
```
