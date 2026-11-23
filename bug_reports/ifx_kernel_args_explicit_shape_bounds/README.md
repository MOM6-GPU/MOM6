# ifx: explicit-shape arrays overflow the 2 KiB kernel argument limit

## Summary

On Intel GPUs (PVC) a kernel's arguments must fit in 2048 bytes. ifx passes each
explicit-shape array referenced in an offloaded loop as **one pointer plus four
separate 8-byte bounds/stride values**, 40 bytes per array, even when every array
has the same bounds expressions. An allocatable array costs only one 8-byte pointer
to its descriptor.

So a loop that touches about 50 explicit-shape arrays, which is common for
automatic arrays declared as `real :: a(isd:ied,jsd:jed,nz)`, produces a kernel
that cannot be built:

```
LEVEL_ZERO message: 'error: Total size of kernel arguments exceeds limit! Total arguments size: 2176, limit: 2048'
LEVEL_ZERO message: 'in kernel: 'mom_set_visc_mp_set_viscous_bbl_''
omptarget fatal error 0: "the plugin backend is in an invalid or unsupported state" failed to load images on device '0'
```

Two problems to report:

1. **Redundant arguments.** Arrays whose bounds are the same expressions
   (`isd:ied, jsd:jed, nz`) each get their own copies of those values. Sharing them
   would avoid the limit in practice.
2. **No compile-time diagnostic for JIT builds.** With the default JIT target
   (`spir64`), compilation and linking succeed and the failure only appears when the
   GPU image is loaded at run time. The truncated kernel name in the message
   (`mom_set_visc_mp_set_viscous_bbl_`) doesn't say which of several kernels in the
   routine is too large; the full name has the line number
   (`__omp_offloading_..._set_viscous_bbl__l550`). Ideally the compiler would pass
   large argument lists through a buffer rather than fail.

## Environment

- Compiler: `ifx (IFX) 2026.1.0 20260617`
- System: Aurora (Intel Data Center GPU Max / PVC, Level Zero)

## Reproduce

```bash
./run.sh
```

`reproducer.F90` fills 60 automatic arrays with bounds `(isd:ied,jsd:jed,nz)` in
a single `do concurrent` loop.

| Build          | Target                       | Result                                               |
|----------------|------------------------------|------------------------------------------------------|
| bug_aot        | `spir64_gen -device pvc`     | **link fails**: arguments size 2544, limit 2048      |
| workaround_aot | same, `-DWORKAROUND`         | links                                                |
| bug_jit        | `spir64`                     | links; **fails at run time** on the GPU              |
| workaround_jit | `spir64`, `-DWORKAROUND`     | links; prints `PASS` on the GPU                      |

The AOT build reports the error on a login node, without a GPU.

## Measurements

Kernel parameter counts were read from the device code with
`clang-offload-bundler -unbundle` and `llvm-spirv -spirv-ext=+all -spirv-text`.
These are for one `do concurrent (k=1:nz, j=jsd:jed, i=isd:ied)` loop that
writes to N arrays:

| Arrays                       | N = 10           | N = 20           | Per array          |
|------------------------------|------------------|------------------|--------------------|
| explicit-shape, automatic    | 68 args, 544 B   | 118 args, 944 B  | 5 args, 40 B       |
| explicit-shape, dummy        | 68 args, 544 B   | 118 args, 944 B  | 5 args, 40 B       |
| allocatable                  | 23 args, 184 B   | 33 args, 264 B   | 1 arg, 8 B         |

## Impact on MOM6

Two kernels in `set_viscous_BBL` (`src/parameterizations/vertical/MOM_set_viscosity.F90`)
exceed the limit:

| Kernel                                       | Arguments | Size   |
|----------------------------------------------|-----------|--------|
| `do concurrent (j=jstart:Jeq)` at line 550   | 272       | 2176 B |
| `!$omp target teams loop collapse(2)` at 845 | 264       | 2112 B |

About 160 of the arguments in each are compiler temporaries holding array bounds.

## Workaround

Either reduce the number of explicit-shape arrays one kernel touches (make the
local 2D/3D work arrays allocatable), or split the loop into several kernels.
