module m
  implicit none
  real, parameter :: tab(0:3) = [1.0, 2.0, 3.0, 4.0]
  !$omp declare target to(tab)
end module
