# ifx: ICE for `do concurrent` with an array `reduce(+)` plus `reduce(max)`

**Status: confirmed compiler crash.** The runtime results of the other cases are correct.

## Summary

A `do concurrent` that has both an array sum reduction and scalar `max` reductions crashes
the device compile:

```fortran
do concurrent (j=1:nj, i=1:ni) local(e, k) reduce(+: s) reduce(max: smax, mpos)
  do k=1,nk ; e(k) = int(a(i,j), i8) * k ; enddo
  smax = max(smax, int(a(i,j), i8))
  if (a(i,j) > mpos) mpos = a(i,j)
  s(:) = s(:) + e(:)
enddo
```

```
error #5633: **Internal compiler error: segmentation violation signal raised**
```

Each reduction on its own compiles and gives the exact result on the GPU, at `-O0` and
`-O3`. So does the same array reduction written as an `!$omp target teams loop`.

This case was written while checking MOM6's reproducing sum (`increment_block_ints`), which
has this shape. The wrong sums in MOM6 turned out to be a different bug:
`../ifx_map_noncontiguous_section`.

## Environment

- Compiler: `ifx (IFX) 2026.1.0 20260617`
- Flags: `-qopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent`
- System: Aurora (Intel GPU, `spir64` offload target)

## Reproduce

```bash
./run.sh     # the -DCASE3 compile check needs no GPU; the runs do
```

```
=== -DCASE3 compile check: error #5633
=== ifx -O3  (columns: s(1) got, s(1) expected, s(nk) error)
reduce(+: s(:))                         ok          36119600      36119600             0
reduce(max: smax, mpos)                 ok          36119600      36119600             0
omp target teams loop reduction(+: s)   ok          36119600      36119600             0
PASS
```
