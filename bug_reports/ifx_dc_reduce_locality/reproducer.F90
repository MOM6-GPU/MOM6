! ifx reproducer (needs a GPU): Fortran 2023 `reduce` locality in an offloaded do concurrent.
!
! Compiler: ifx (IFX) 2026.1.0 20260617 (Aurora)
!   ifx -qopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent reproducer.F90
!
! MOM6 (set_dtbt in MOM_barotropic.F90) computes a minimum with
!   do concurrent (j=js:je, i=is:ie) reduce(min:min_max_dt2)
!     if (Idt_max2 * min_max_dt2 > 1.0) min_max_dt2 = 1.0 / Idt_max2
!   enddo
! On Aurora the result was the initial value (1e38): dtbt became huge and the model
! stopped with "btstep: number of barotropic step (nstep+nfilter) is 0".
!
! Result on a PVC node: plain min/max/+ reductions are correct.  The MOM6-shaped
! conditional minimum is WRONG at -O3 (it returns the initial 1e38) in BOTH the
! do concurrent and the omp target teams loop forms, and is correct at -O0.
! Suspected cause: each private copy of a min reduction starts at huge(); val*huge()
! overflows to +Inf, and the default -fp-model fast assumes no infinities, so the test
! `val * r > 1.0` is folded to false and no copy is ever updated.  run.sh also builds
! -O3 -fp-model precise to test this.
!
! Each case is computed with do concurrent + reduce, and with the equivalent
! `!$omp target teams loop reduction(...)` as a reference.  The expected value is also
! computed on the host.
program reproducer
  implicit none
  integer, parameter :: dp = kind(1.0d0)  ! MOM6 builds with -r8
  integer, parameter :: ni = 300, nj = 200
  real(dp), allocatable :: a(:,:)
  real(dp) :: rmin, rmax, rsum, rmin_cond, ref_min, ref_max, ref_sum, ref_cond, val, vmax
  integer :: i, j, nfail

  allocate(a(ni,nj))
  do j=1,nj ; do i=1,ni
    a(i,j) = 1.0_dp + real(mod(i*7 + j*13, 997), dp)   ! values 1..997, min 1 at i=j=... somewhere
  enddo ; enddo
  a(123,45) = 0.25                              ! unique minimum
  a(17,190) = 5000.0                            ! unique maximum
  ref_min = minval(a) ; ref_max = maxval(a) ; ref_sum = 0.0
  do j=1,nj ; do i=1,ni ; ref_sum = ref_sum + a(i,j) ; enddo ; enddo
  ref_cond = 1.0 / maxval(a)                    ! MOM6 shape: min of 1/a, via a conditional

  !$omp target enter data map(to: a)
  nfail = 0

  ! --- do concurrent with reduce locality (offloaded with -fopenmp-target-do-concurrent)
  rmin = huge(rmin) ; rmax = -huge(rmax) ; rsum = 0.0 ; rmin_cond = 1.0e38
  do concurrent (j=1:nj, i=1:ni) reduce(min:rmin)
    rmin = min(rmin, a(i,j))
  enddo
  do concurrent (j=1:nj, i=1:ni) reduce(max:rmax)
    rmax = max(rmax, a(i,j))
  enddo
  do concurrent (j=1:nj, i=1:ni) reduce(+:rsum)
    rsum = rsum + a(i,j)
  enddo
  do concurrent (j=1:nj, i=1:ni) reduce(min:rmin_cond) local(val)
    val = a(i,j)                                ! like Idt_max2
    if (val * rmin_cond > 1.0) rmin_cond = 1.0 / val
  enddo
  call check('do concurrent reduce(min)         ', rmin, ref_min)
  call check('do concurrent reduce(max)         ', rmax, ref_max)
  call check('do concurrent reduce(+)           ', rsum, ref_sum)
  call check('do concurrent reduce(min), MOM6   ', rmin_cond, ref_cond)

  ! --- explicit OpenMP reference
  rmin = huge(rmin) ; rmax = -huge(rmax) ; rsum = 0.0 ; rmin_cond = 1.0e38
  !$omp target teams loop collapse(2) reduction(min:rmin)
  do j=1,nj ; do i=1,ni ; rmin = min(rmin, a(i,j)) ; enddo ; enddo
  !$omp target teams loop collapse(2) reduction(max:rmax)
  do j=1,nj ; do i=1,ni ; rmax = max(rmax, a(i,j)) ; enddo ; enddo
  !$omp target teams loop collapse(2) reduction(+:rsum)
  do j=1,nj ; do i=1,ni ; rsum = rsum + a(i,j) ; enddo ; enddo
  !$omp target teams loop collapse(2) reduction(min:rmin_cond) private(val)
  do j=1,nj ; do i=1,ni
    val = a(i,j)
    if (val * rmin_cond > 1.0) rmin_cond = 1.0 / val
  enddo ; enddo
  call check('omp target teams loop min         ', rmin, ref_min)
  call check('omp target teams loop max         ', rmax, ref_max)
  call check('omp target teams loop +           ', rsum, ref_sum)
  call check('omp target teams loop min, MOM6   ', rmin_cond, ref_cond)

  ! --- workaround: reduce the maximum of val, then apply the conditional once on the host
  vmax = 0.0_dp
  do concurrent (j=1:nj, i=1:ni) reduce(max:vmax)
    vmax = max(vmax, a(i,j))
  enddo
  rmin_cond = 1.0e38
  if (vmax * rmin_cond > 1.0) rmin_cond = 1.0 / vmax
  call check('workaround: reduce(max) + host    ', rmin_cond, ref_cond)

  !$omp target exit data map(delete: a)
  if (nfail == 0) then
    print '(a)', 'PASS'
  else
    print '(a,i0,a)', 'FAIL: ', nfail, ' reduction(s) wrong'
    error stop 1
  endif

contains

  subroutine check(label, got, expect)
    character(len=*), intent(in) :: label
    real(dp), intent(in) :: got, expect
    logical :: ok
    ok = abs(got - expect) <= 1.0e-6 * max(abs(expect), 1.0e-30_dp)
    print '(a,a,es14.6,a,es14.6,a)', label, ' got ', got, '  expected ', expect, merge('  ok   ', '  WRONG', ok)
    if (.not. ok) nfail = nfail + 1
  end subroutine check

end program reproducer
