# ifx -O3: a conditional min reduction on the GPU returns its initial value

## Summary

On a PVC GPU, this minimum reduction returns the host's initial value (1e38) at `-O3`,
and the correct value at `-O0`:

```fortran
r = 1.0e38
do concurrent (j=1:nj, i=1:ni) reduce(min:r) local(val)
  val = a(i,j)
  if (val * r > 1.0) r = 1.0 / val
enddo
```

The equivalent `!$omp target teams loop collapse(2) reduction(min:r)` fails the same way,
so this is not specific to `do concurrent`. Plain `min(r, x)`, `max` and `+` reductions
are correct in both forms.

## Measured on a GPU node (`run.sh`)

| Case | -O0 | -O3 |
|---|---|---|
| `reduce(min)`, `reduce(max)`, `reduce(+)` (`do concurrent`) | ok | ok |
| same with `omp target teams loop reduction(...)` | ok | ok |
| conditional min, `do concurrent reduce(min:r)` | ok | **WRONG: 1.0E+38** |
| conditional min, `omp target teams loop reduction(min:r)` | ok | **WRONG: 1.0E+38** |
| conditional min, both forms, `-O3 -fp-model precise` | | ok |
| workaround: `reduce(max)` + host test | ok | ok |

`-fp-model precise` makes the conditional min correct, which confirms the mechanism below.

## Cause (confirmed with `-fp-model precise`)

Each thread's private copy of a `min` reduction starts at `huge(r)`, about 1.8e308, not at
the host's 1e38. Then `val * r` overflows to `+Inf`. ifx's default `-fp-model fast`
assumes no infinities, so at `-O3` the test `val * r > 1.0` may be folded to false. No
private copy is then ever updated, and the combined result is the host's initial value.
The `-fp-model precise` build is correct, which confirms this. It's still worth reporting:
the identity value of the reduction is chosen by the implementation, and the user's code
never overflows when run sequentially.

## Environment

- Compiler: `ifx (IFX) 2026.1.0 20260617`
- System: Aurora (Intel Data Center GPU Max / PVC)
- Flags: `-O3 -qopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent`

## Impact on MOM6

`set_dtbt` (`src/core/MOM_barotropic.F90`) computes the barotropic time step limit with
exactly this pattern:

```fortran
min_max_dt2 = 1.0e38*US%s_to_T**2
do concurrent (j=js:je, i=is:ie) DO_LOCALITY(reduce(min:min_max_dt2))
  Idt_max2 = ...
  if (Idt_max2 * min_max_dt2 > 1.0) min_max_dt2 = 1.0 / Idt_max2
enddo
dtbt_max = sqrt(min_max_dt2 / dgeo_de)
```

On Aurora `min_max_dt2` stayed at 1e38, so `dtbt` was about 1e19 s and the model stopped
with:

```
FATAL: btstep: number of barotropic step (nstep+nfilter) is 0
```

All 26 `reduce` locality uses in MOM6 were checked. Only this one updates the reduction
variable through a test that multiplies it; the rest are plain `+` or `max` reductions.

## Workaround

Under `-DIFX_WORKAROUNDS_MOM6`, `set_dtbt` reduces the **maximum** of `Idt_max2`, which
works, and then applies the original test once on the host:

```fortran
max_Idt2 = 0.0
do concurrent (j=js:je, i=is:ie) DO_LOCALITY(reduce(max:max_Idt2))
  Idt_max2 = ...
  max_Idt2 = max(max_Idt2, Idt_max2)
enddo
if (max_Idt2 * min_max_dt2 > 1.0) min_max_dt2 = 1.0 / max_Idt2
```

This gives the same `1/max(Idt_max2)` that the original loop converges to. The order of
the original reduction was unspecified anyway.
