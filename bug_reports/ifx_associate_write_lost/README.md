# ifx: writes to an associate name in an offloaded `do concurrent` are lost

**Status: confirmed.** Wrong results at `-O0` and `-O3`, on the GPU and also with
`OMP_TARGET_OFFLOAD=DISABLED`. The same source built without `-qopenmp` is correct.
No error or warning is printed.

## Summary

With `-fopenmp-target-do-concurrent`, an assignment to an `ASSOCIATE` name inside a
`do concurrent` has no effect. This holds whatever the associate name refers to: a
component of a derived type (pointer or not), or a plain allocatable array. Reading through
an associate name works (see `../ifx_associate_component_kernel`).

```fortran
associate(ssh_rint => CS%ssh_rint)
do concurrent (j=1:n, i=1:n)
  ssh_rint(i,j) = ssh_rint(i,j) + dt * ssh(i,j)   ! ssh_rint is unchanged afterwards
enddo
end associate
```

The same loop written as `CS%ssh_rint(i,j) = ...` is correct. Three forms work:
- the associate name used inside an explicit `!$omp target teams loop` instead of
  `do concurrent`;
- a pointer (`p => CS%ssh_rint`) inside the `do concurrent`;
- the array passed as a dummy argument.

## Impact on MOM6

`step_MOM` (`src/core/MOM.F90`) uses associate names to avoid mapping all of `CS`, in five
`do concurrent` loops:
- the reset and accumulation of `ssh_rint`;
- `ave_ssh_ibc`;
- the reset of the tracer transports `uhtr` and `vhtr`.

The lost writes left the time-mean sea surface height at its initial value, and stopped
the tracer transports from being reset between tracer steps.

The workaround (`IFX_WORKAROUNDS_MOM6`) uses an explicit `!$omp target teams loop` at those
five loops. To find other cases, run `ocean_only/jobs/tools/assoc_dc_writes.py`, which lists
`do concurrent` loops that assign to an associate name.

## Environment

- Compiler: `ifx (IFX) 2026.1.0 20260617`
- Flags: `-qopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent`
- System: Aurora (Intel GPU, `spir64` offload target)

## Reproduce

```bash
./run.sh
```

The script builds without OpenMP, then with offload at `-O0` and `-O3`, and runs each
offload build both with offload disabled and on the GPU. Only the "via associate name" line
fails, in every OpenMP build:

```
via associate name : sum =         0.0  expect      7744.0
via CS%ssh_rint    : sum =      7744.0  expect      7744.0
WORKAROUND associate + omp loop : sum =      7744.0  expect      7744.0
WORKAROUND pointer + do conc.   : sum =      7744.0  expect      7744.0
```
