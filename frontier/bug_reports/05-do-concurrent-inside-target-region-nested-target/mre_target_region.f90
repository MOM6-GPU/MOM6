program v
  implicit none
  integer, parameter :: ni = 40, nj = 40
  real :: a(ni,nj)
  integer :: i, j
  a = 1.0
  !$omp target map(tofrom: a)
  do j = 1, nj
    do concurrent (i=1:ni)
      a(i,j) = a(i,j) + real(i+j)
    enddo
  enddo
  !$omp end target
  print *, 'mre_target_region', sum(a), merge('OK   ','WRONG', abs(sum(a)-67200.)<1.)
end program
