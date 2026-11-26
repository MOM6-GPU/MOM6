! Nested do concurrent loops reduce into the same variable inside an offloaded do concurrent.
! Only with -g.  Original compiler: "conflicting debug info for argument" ... "failed to create the LLVM module"
!   amdflang -c -g -O2 -fopenmp --offload-arch=gfx90a -fdo-concurrent=device
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
