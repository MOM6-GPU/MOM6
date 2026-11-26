program p
  implicit none
  integer, parameter :: n = 1600
  integer(8) :: bs(4)
  integer :: i
  bs(:) = 0
  do concurrent (i=1:n) reduce(+: bs)
    bs(:) = bs(:) + i
  enddo
  print '(a,4i12,a,i10)', 'do concurrent reduce(+: array) ', int(bs), '  expected', n*(n+1)/2
end program
