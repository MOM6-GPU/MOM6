program p
  implicit none
  integer, parameter :: n = 1600
  integer(8) :: bs(4)
  integer :: i
  bs(:) = 0
  !$omp target teams loop reduction(+: bs) map(tofrom: bs)
  do i = 1, n
    bs(:) = bs(:) + i
  enddo
  print '(a,4i12,a,i10)', 'omp_loop_i8 ', int(bs), '  expected', n*(n+1)/2
end program
