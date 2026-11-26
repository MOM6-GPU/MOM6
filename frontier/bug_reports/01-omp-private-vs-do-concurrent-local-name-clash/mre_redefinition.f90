subroutine s(a, n)
  integer :: n
  real :: a(n)
  integer :: i, ii
  do concurrent (ii=1:n) local(i)
    i = ii
    a(i) = 0.
  enddo
  !$omp parallel do private(i)
  do ii = 1, n
    i = ii
    a(i) = 1.
  enddo
end subroutine
