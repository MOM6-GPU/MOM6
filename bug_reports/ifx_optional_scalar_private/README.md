# Investigation (not reproduced): optional scalar made PRIVATE in an offloaded loop

**Status: not a confirmed compiler bug.** The MRE passes on a GPU node at `-O0` and `-O3`.
Don't file it.

## Why it was suspected

ifx warns, for an optional scalar argument read inside an offloaded `do concurrent`:

```
warning #5590: Optional parameter GTOT_EST is being implicitly added as a PRIVATE clause.
```

A PRIVATE copy would be uninitialized on the device. In MOM6 this warning appears for
`gtot_est` (`set_dtbt`), `add_max` (`find_face_areas`) and `rho_ref` (Wright EOS 2D/3D
density). The `gtot_est`/`add_max` path computes `dtbt` at initialization, and the model
stops with `btstep: number of barotropic step (nstep+nfilter) is 0`.

## Result

`reproducer.F90` reads a present optional scalar in an offloaded `do concurrent`, both
directly and inside an `if (present(...))` branch like `set_dtbt`. On a PVC node both
cases print the expected values, with and without `-DWORKAROUND` (which copies the value
into a local first), at `-O0` and `-O3`. So the warning's PRIVATE is harmless in this form.

## MOM6

The local-copy workaround is still applied under `IFX_WORKAROUNDS_MOM6` in `set_dtbt`,
`find_face_areas` and the two Wright density routines. It's harmless, but it didn't fix
the `nstep` failure, so it's a candidate for removal once the real cause is known.
