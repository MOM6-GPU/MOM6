! ifx reproducer (needs a GPU): do concurrent with an ARRAY sum reduction, reduce(+: s(:)),
! offloaded with -fopenmp-target-do-concurrent.  Modeled on MOM6's reproducing sum
! (increment_block_ints in MOM_coms.F90), which gave wrong means on the GPU.
!
!   ifx -O3 -qopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent reproducer.F90
!
! Every case is compared against the exact integer result computed on the host.
! Case 3 (array + reduction together with max reductions, MOM6's shape) is only built with
! -DCASE3: with ifx 2026.1.0 it crashes the device compile (ICE #5633).
program reproducer
  implicit none
  integer, parameter :: i8 = selected_int_kind(18)
  integer, parameter :: ni = 44, nj = 40, nk = 6
  integer(i8) :: s(nk), ref(nk), e(nk), smax, refmax
  real :: a(ni,nj), mpos, refmpos
  integer :: i, j, k, nfail

  do j=1,nj ; do i=1,ni ; a(i,j) = real(i + 1000*j) ; enddo ; enddo
  ref(:) = 0 ; refmax = 0 ; refmpos = 0.
  do j=1,nj ; do i=1,ni
    do k=1,nk ; ref(k) = ref(k) + int(a(i,j), i8) * k ; enddo
    refmax = max(refmax, int(a(i,j), i8)) ; refmpos = max(refmpos, a(i,j))
  enddo ; enddo
  !$omp target enter data map(to: a)
  nfail = 0

  ! 1. array sum reduction only
  s(:) = 0
  do concurrent (j=1:nj, i=1:ni) local(e, k) reduce(+: s)
    do k=1,nk ; e(k) = int(a(i,j), i8) * k ; enddo
    s(:) = s(:) + e(:)
  enddo
  call check('reduce(+: s(:))                       ', all(s == ref))

  ! 2. scalar max reductions only
  smax = 0 ; mpos = 0.
  do concurrent (j=1:nj, i=1:ni) reduce(max: smax, mpos)
    smax = max(smax, int(a(i,j), i8))
    if (a(i,j) > mpos) mpos = a(i,j)
  enddo
  call check('reduce(max: smax, mpos)               ', smax == refmax .and. mpos == refmpos)

#ifdef CASE3
  ! 3. both together, like MOM6's increment_block_ints
  s(:) = 0 ; smax = 0 ; mpos = 0.
  do concurrent (j=1:nj, i=1:ni) local(e, k) reduce(+: s) reduce(max: smax, mpos)
    do k=1,nk ; e(k) = int(a(i,j), i8) * k ; enddo
    smax = max(smax, int(a(i,j), i8))
    if (a(i,j) > mpos) mpos = a(i,j)
    s(:) = s(:) + e(:)
  enddo
  call check('reduce(+: s(:)) + reduce(max: ...)    ', all(s == ref) .and. smax == refmax .and. mpos == refmpos)

#endif
  ! 4. reference: explicit OpenMP array reduction
  s(:) = 0
  !$omp target teams loop collapse(2) private(e, k) reduction(+: s)
  do j=1,nj ; do i=1,ni
    do k=1,nk ; e(k) = int(a(i,j), i8) * k ; enddo
    s(:) = s(:) + e(:)
  enddo ; enddo
  call check('omp target teams loop reduction(+: s) ', all(s == ref))

  if (nfail == 0) then ; print '(a)', 'PASS' ; else ; print '(a,i0,a)', 'FAIL: ', nfail, ' wrong' ; error stop 1 ; endif
contains
  subroutine check(label, ok)
    character(len=*), intent(in) :: label
    logical, intent(in) :: ok
    if (.not. ok) nfail = nfail + 1
    print '(a,a,3i14)', label, merge('  ok    ', '  WRONG ', ok), s(1), ref(1), s(nk)-ref(nk)
  end subroutine check
end program reproducer
