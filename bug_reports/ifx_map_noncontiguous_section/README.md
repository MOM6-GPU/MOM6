# ifx: an offloaded loop over a non-contiguous dummy array reads wrong data

**Status: confirmed.** Wrong results at `-O0` and `-O3` on the GPU, in both `do concurrent`
and `!$omp target teams loop`, with no error.

## Summary

Suppose an assumed-shape dummy argument is a non-contiguous section of a larger array, such
as the interior of an array with halos, `full(1:44,1:40)` of a `52 x 48` array. A device
loop over that dummy then reads wrong values for its trailing columns.

```fortran
real function dev_sum(a)          ! a(:,:), assumed shape
  ...
  do concurrent (j=1:n2, i=1:n1) reduce(+:t) ; t = t + a(i,j) ; enddo

print *, dev_sum(full(1:44,1:40))   ! ones inside the section: 1496, expected 1760
```

1760 − 1496 = 264 = 6 columns × 44. That's consistent with the runtime transferring
`size(a)` consecutive elements from the start of the section, instead of the strided extent
the section covers. The missing columns read as zero.

## Impact on MOM6

The checksum routines call `reproducing_sum(array(isc:iec,jsc:jec))`, and the reproducing
sum's block loop (`increment_block_ints` in `src/framework/MOM_coms.F90`) runs on the device.
Every DEBUG checksum mean was about 15% low, and the debug run then aborted with an overflow
in `reproducing_EFP_sum`.

The workaround (`IFX_WORKAROUNDS_MOM6`): `increment_block_ints` copies a non-contiguous
argument into a contiguous temporary before the device loop. That's bitwise identical,
because only the memory layout changes.

## Notes

- Using `size(a,1)` and `size(a,2)` directly as `do concurrent` bounds in this function
  crashes the compiler (ICE #5633). The reproducer copies them into locals first.

## Environment

- Compiler: `ifx (IFX) 2026.1.0 20260617`
- Flags: `-qopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent`
- System: Aurora (Intel GPU, `spir64` offload target)

## Reproduce

```bash
./run.sh     # needs a GPU node
```

```
contiguous array          (do concurrent) : sum =      1760.0  (expect  1760.0)
interior section full(1:ni,1:nj) (do conc.): sum =      1496.0  (expect  1760.0)
interior section full(1:ni,1:nj) (omp)     : sum =      1496.0  (expect  1760.0)
FAIL
```
