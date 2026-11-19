# ifx: `declare target` separate module procedures can't be used from device code

## Summary

With ifx there is no placement of `!$omp declare target` that makes a separate
module procedure (interface in a module, body in a submodule) usable from every
kind of offloaded code:

| Directive placement | Result |
|---|---|
| interface **and** body (conforming) | **compile error #8682**: "Multiple !$OMP DECLARE TARGET declarations" |
| interface only | compiles, links, and callers offload and call `f`, but **the body is never compiled for the device**. The GPU image fails to load at run time with "Module link failed". |
| body only | the body is compiled for the device and calls from `!$omp target` regions work, but **a `do concurrent` that calls `f` is not offloaded** (warning #5476) |

Other spellings in the submodule, such as `declare target(f)`,
`declare target enter(f)` or `to(f)` at submodule scope or in the body, all give
error #8682 when the interface also has the directive. So ifx knows `f` is a
device procedure, but never generates device code for it.

```fortran
module parent
  interface
    elemental module function f(x) result(a)
      real, intent(in) :: x
      real :: a
      !$omp declare target
    end function f
  end interface
end module parent

submodule (parent) child
contains
  module procedure f
    !$omp declare target          ! error #8682; without it, f has no device code
    a = 2.0 * x
  end procedure f
end submodule child
```

## Why this looks like a compiler bug

OpenMP's Fortran restrictions for `declare target` say that a directive specified
in an interface block for a procedure must match a `declare target` directive in
the definition of that procedure. For a separate module procedure, the parent
module's interface body is that interface block and the `module procedure` body
is the definition. So the first row should be the conforming form, not an error.
Even setting conformance aside, the interface-only form should not silently
produce a call to a device function that is never defined.

Please check the exact wording against the OpenMP version you report under before
filing.

## Environment

- Compiler: `ifx (IFX) 2026.1.0 20260617`
- System: Aurora (Intel GPU, `spir64` offload target)

## Reproduce

```bash
./run.sh
```

For every build that compiles, `run.sh` also extracts the device code
(`clang-offload-bundler -unbundle`, then `llvm-spirv -spirv-text`). It reports
whether that code defines and/or calls `f`, so the problem is visible without a GPU:

```
=== both:       compile: FAILED  error #8682: Multiple !$OMP DECLARE TARGET declarations.
=== iface_only: compile: OK      device code: defines f: 0, calls f: 1
=== workaround: compile: OK      device code: defines f: 1, calls f: 0
```

On a GPU node the `iface_only` binary fails to load its device image, and the
`workaround` binary prints `PASS`.

The `#8682` error happens with or without `-fopenmp-targets`, and at both `-O0`
and `-O3`.

## Impact on MOM6

`exp_repro` uses this pattern: the interface is in
`src/framework/MOM_intrinsic_functions.F90`, and the body is in the submodule
`src/framework/intrinsics/MOM_exp.F90`. It's called on the device from
`set_viscous_ML` in `MOM_set_viscosity.F90`.

- **First workaround (interface only):** compiled, but the first GPU run failed:
  ```
  "PluginInterface" error: Failure to load binary image ... "unknown or internal error" Module link failed
  ```
  The device code of `MOM_set_viscosity.o` imports
  `mom_intrinsic_functions_mp_exp_repro_`, and no object exported it.
- **Current workaround (body only):** under `-DIFX_WORKAROUNDS_MOM6`, the
  directive is omitted from the interface and kept in the body. Both MOM6 call
  sites are inside an explicit `!$omp target teams` region, so they still compile
  to device calls.
- **Limitation:** with the macro on, any future `do concurrent` that calls
  `exp_repro` will not be offloaded (warning #5476).
