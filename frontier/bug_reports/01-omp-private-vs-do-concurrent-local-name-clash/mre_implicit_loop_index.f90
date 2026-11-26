! No explicit private clause: the parallel do loop index j is implicitly private.
subroutine s(a, n)
  integer :: n
  real :: a(n,n)
  integer :: j, jj
  !$omp parallel do default(shared)
  do j = 1, n
    a(:,j) = 1.
  enddo
  do concurrent (jj=1:n) local(j)
    j = jj
    a(1,j) = 0.
  enddo
end subroutine
