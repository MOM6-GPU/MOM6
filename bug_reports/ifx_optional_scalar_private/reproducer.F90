! ifx reproducer (needs a GPU): a PRESENT optional scalar argument read inside an offloaded
! do concurrent gets the wrong value.
!
! Compiler: ifx (IFX) 2026.1.0 20260617 (Aurora)
!   ifx -qopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent reproducer.F90
!   -> warning #5590: Optional parameter S is being implicitly added as a PRIVATE clause.
!
! PRIVATE (not FIRSTPRIVATE) means each device thread gets an uninitialized copy, so the
! value passed by the caller never reaches the kernel.  In MOM6, set_dtbt(gtot_est=...)
! and find_face_areas(add_max=...) read their optional scalars like this; dtbt came out
! huge and the model stopped with "btstep: number of barotropic step (nstep+nfilter) is 0".
!
! -DWORKAROUND copies the optional argument into a local variable first.
module repro_mod
  implicit none
  private
  public :: fill, fill_branch
contains

!> x(:) = s, with s an optional argument (present in this test)
subroutine fill(x, n, s)
  integer,        intent(in)    :: n    !< Array size
  real,           intent(inout) :: x(n) !< Output [arbitrary]
  real, optional, intent(in)    :: s    !< Fill value [arbitrary]
  integer :: i
#ifdef WORKAROUND
  real :: s_loc
  s_loc = 0.0 ; if (present(s)) s_loc = s
  do concurrent (i=1:n)
    x(i) = s_loc
  enddo
#else
  do concurrent (i=1:n)
    x(i) = s
  enddo
#endif
end subroutine fill

!> Like MOM6's set_dtbt: the loop is only reached when s is present
subroutine fill_branch(x, n, s)
  integer,        intent(in)    :: n    !< Array size
  real,           intent(inout) :: x(n) !< Output [arbitrary]
  real, optional, intent(in)    :: s    !< Fill value [arbitrary]
  integer :: i
#ifdef WORKAROUND
  real :: s_loc
#endif
  if (.not. present(s)) then
    x(:) = -1.0
  else
#ifdef WORKAROUND
    s_loc = s
    do concurrent (i=1:n)
      x(i) = s_loc + 1.0
    enddo
#else
    do concurrent (i=1:n)
      x(i) = s + 1.0
    enddo
#endif
  endif
end subroutine fill_branch

end module repro_mod

program reproducer
  use repro_mod, only : fill, fill_branch
  implicit none
  integer, parameter :: n = 64
  real :: x(n)
  integer :: nfail

  nfail = 0
  x(:) = 0.0
  !$omp target data map(tofrom: x)
  call fill(x, n, 42.0)
  !$omp end target data
  print '(a,2f10.3,a)', 'fill(s=42):         x(1), x(n) = ', x(1), x(n), '   (expect 42)'
  if (any(x /= 42.0)) nfail = nfail + 1

  x(:) = 0.0
  !$omp target data map(tofrom: x)
  call fill_branch(x, n, 7.0)
  !$omp end target data
  print '(a,2f10.3,a)', 'fill_branch(s=7):   x(1), x(n) = ', x(1), x(n), '   (expect 8)'
  if (any(x /= 8.0)) nfail = nfail + 1

  if (nfail == 0) then
    print '(a)', 'PASS'
  else
    print '(a)', 'FAIL'
    error stop 1
  endif
end program reproducer
