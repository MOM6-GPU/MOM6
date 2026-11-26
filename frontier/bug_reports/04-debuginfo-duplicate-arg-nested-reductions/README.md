# 04: `-g` + two nested `do concurrent` reductions of one variable: "conflicting debug info for argument"

**Compiler:** AMD flang 24.0.0git, AFAR drop 24.4.0 (`af5d6a97`). Also present in earlier drops.
**Severity:** hard error on valid code, only with `-g` (MOM6 builds use `-g`).
**Component:** LLVM OpenMPIRBuilder (outlining), not the flang frontend.

## MRE
```fortran
subroutine s(n, mu, mv, dk)
  integer, intent(in) :: n
  logical, intent(in) :: mu(n,n), mv(n,n)
  integer, intent(out) :: dk(n)
  integer :: j, k, t
  do concurrent (k=1:n)
    t = 0
    do concurrent (j=1:n, mu(j,k)) reduce(max:t)
      t = 1
    end do
    do concurrent (j=1:n, mv(j,k)) reduce(max:t)
      t = 1
    end do
    dk(k) = t
  end do
end subroutine
```
```
$ amdflang -g -c -O2 -fopenmp --offload-arch=gfx90a -fdo-concurrent=device mre_nested_reduction_debuginfo.f90
conflicting debug info for argument
#dbg_declare(ptr %5, !122, !DIExpression(), !110)
!117 = !DILocalVariable(name: "t", arg: 6, scope: !71, file: !2, line: 8, type: !3)
!122 = !DILocalVariable(name: "t", arg: 6, scope: !71, file: !2, line: 14, type: !3)
...
error: failed to create the LLVM module
```
Without `-g` it compiles. `./run.sh` shows both.

## Likely cause
When the offloaded region is outlined, each of the two reductions of `t` contributes a
`DILocalVariable` for the same outlined argument (#6), from lines 8 and 14. The IR verifier rejects
two different variables for one argument. One `DILocalVariable` per outlined argument is needed.

## Workaround
Drop `-g` for the affected file.
