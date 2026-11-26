# 07: `!$omp target teams loop reduction(+: array)`: "operand #0 does not dominate this use"

**Compiler:** AMD flang 24.0.0git, AFAR drop 24.4.0 (ROCm/llvm-project `af5d6a9790939cc301486abeec5a51ee48f59c18`)
**Severity:** compile error on **valid code**. Any `-fopenmp`, with or without offload, any -O.

## MRE
```fortran
  integer(8) :: bs(4)
  bs(:) = 0
  !$omp target teams loop reduction(+: bs) map(tofrom: bs)
  do i = 1, n
    bs(:) = bs(:) + i
  enddo
```
```
$ amdflang -c -fopenmp mre_teams_loop_array_reduction.f90
error: loc("mre_teams_loop_array_reduction.f90":7:9): operand #0 does not dominate this use
error: verification of lowering to FIR failed
```
`target parallel loop` and `target teams distribute parallel do` with the same clause compile (and
the latter gives correct results, see 06). The array reduction is lost/misplaced in the teams-loop
lowering.

## Hit in MOM6
Not in dev/gpu as written; it is the obvious alternative workaround for 06, which is why it was found.

## Workaround
Use `target teams distribute parallel do`.
