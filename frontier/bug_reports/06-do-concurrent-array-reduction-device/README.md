# 06: `do concurrent ... reduce(+: array)` offloaded to the GPU gives a memory fault or garbage

**Compiler:** AMD flang 24.0.0git, AFAR drop 24.4.0 (ROCm/llvm-project `af5d6a9790939cc301486abeec5a51ee48f59c18`)
**Severity:** wrong results / GPU memory fault on **valid code**.
**Needs:** `-fopenmp --offload-arch=gfx90a -fdo-concurrent=device`, a GPU.

## Summary
A `reduce` locality spec on an **array** in a `do concurrent` mapped to the device is broken. Scalar
reductions (`+`, `max`, `min`, `.or.`) on the device are correct; the array reduction on the host
(`-fdo-concurrent=host`) is correct; the equivalent explicit
`!$omp target teams distribute parallel do reduction(+: array)` is correct.

## MRE
```fortran
  integer(8) :: bs(4)
  bs(:) = 0
  do concurrent (i=1:n) reduce(+: bs)
    bs(:) = bs(:) + i
  enddo
```
`./run.sh`:
```
mre_array_reduce:  Warning: Queue error - HSA_STATUS_ERROR_MEMORY_FAULT     (integer(4), integer(8), real(8) alike)
workaround_omp:    omp distribute parallel do reduction(+: array)  1280800 1280800 1280800 1280800  expected 1280800
```
In a bigger case (array reduction plus `local(e, k)` and a `max` reduction, `bs` not mapped by the
user) it did not fault but returned garbage (`-7115687411245383680` instead of `3312800`).

## Hit in MOM6 (dev/gpu)
`MOM_coms.F90`, `reproducing_sum`: `reduce(+: block_sum)` on the EFP digit array. Every global sum
(mass, energy, ...) is wrong: double_gyre Day-0 mass `4.87E+32` kg instead of `5.28818E+18`.

## Workaround
`MOM_coms.F90`, guarded by `#ifdef AMD_WORKAROUNDS`: the loop is written as
`!$omp target teams distribute parallel do collapse(2) private(...) reduction(+: block_sum) reduction(max: ...)`.
(Not `target teams loop`: see 07.)
