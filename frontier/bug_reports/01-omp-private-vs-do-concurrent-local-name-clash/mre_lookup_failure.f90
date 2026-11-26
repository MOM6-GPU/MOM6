module m
  implicit none
contains
  subroutine s(p, a, n)
    real, intent(in) :: p(n)
    integer, intent(in) :: n
    real, intent(inout) :: a(n)
    integer :: i, ii
    !$omp target map(tofrom: a) map(to: p)
    !$omp loop private(i)
    do ii = 1, n
      i = ii
      a(i) = p(i)
    enddo
    !$omp end target
    do concurrent (ii=1:n) local(i)
      i = ii
      a(i) = 0.
    enddo
  end subroutine
end module
