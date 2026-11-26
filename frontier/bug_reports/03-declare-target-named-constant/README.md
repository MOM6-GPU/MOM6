# 03: `declare target to/enter(<named constant>)` is an error, but `declare target(<named constant>)` only warns

**Compiler:** AMD flang 24.0.0git, AFAR drop 24.4.0 (`af5d6a97`). Also present in earlier drops.
**Severity:** low (inconsistency). Not blocking MOM6, which uses the argument form.

## MRE
```fortran
module m
  real, parameter :: tab(0:3) = [1.0, 2.0, 3.0, 4.0]
  !$omp declare target to(tab)
end module
```
| directive | result |
|-----------|--------|
| `declare target to(tab)` | `error: 'tab' must be an extended list item` (+ PARAMETER warning) |
| `declare target enter(tab)` | same error |
| `declare target(tab)` | only `warning: The entity with PARAMETER attribute is used in a DECLARE TARGET directive` |

`./run.sh` shows the `to(...)` case. Flags: `amdflang -c -fopenmp`.

## Notes
Strictly, OpenMP wants variables or procedures in these clauses, so an error can be argued. But the
clause forms and the argument form should agree, and the existing PARAMETER warning suggests the
intent is to accept named constants with a warning. `OmpStructureChecker::CheckObjectList`
(`flang/lib/Semantics/check-omp-structure.cpp`) rejects them before that warning is reached.

MOM6: `src/framework/intrinsics/MOM_exp_data_n128.F90` (`!$omp declare target(...)` on lookup tables).
