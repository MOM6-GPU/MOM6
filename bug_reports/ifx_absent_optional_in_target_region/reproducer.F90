! ifx reproducer: an absent optional argument referenced inside a target region crashes
! the HOST while the region is being set up, even though the code inside the region
! never touches the argument when it is absent.
!
! Compiler: ifx (IFX) 2026.1.0 20260617 (Aurora)
!   ifx -qopenmp -fopenmp-targets=spir64 reproducer.F90
!   -> compile time: warning #5590: Optional parameter OBC is being implicitly added as a
!      FIRSTPRIVATE clause. Optional parameters will fault if not present.
!   -> run time (GPU node): SIGSEGV on the host, before the kernel is launched.
!
! -DWORKAROUND copies the optional argument into a local pointer (null if absent) and
! uses that inside the region.
module repro_mod
  implicit none
  private
  public :: obc_t, adjust

  !> Something like MOM6's ocean_OBC_type
  type :: obc_t
    integer, allocatable :: segnum(:) !< Segment numbers
  end type obc_t

contains

!> Adds 1 to x, using OBC only if it is present and associated
subroutine adjust(x, n, OBC)
  integer,                         intent(in)    :: n    !< Array size
  real,                            intent(inout) :: x(n) !< Data [arbitrary]
  type(obc_t), optional, pointer                 :: OBC  !< Optional, may be absent
  logical :: use_obc
  integer :: i
#ifdef WORKAROUND
  type(obc_t), pointer :: OBC_loc
  OBC_loc => NULL() ; if (present(OBC)) OBC_loc => OBC
#endif

  use_obc = .false.
  if (present(OBC)) then ; if (associated(OBC)) use_obc = .true. ; endif

  !$omp target map(tofrom: x)
  !$omp loop
  do i=1,n
    x(i) = x(i) + 1.0
#ifdef WORKAROUND
    if (use_obc) then ; if (OBC_loc%segnum(i) /= 0) x(i) = 0.0 ; endif
#else
    if (use_obc) then ; if (OBC%segnum(i) /= 0) x(i) = 0.0 ; endif   ! never runs if absent
#endif
  enddo
  !$omp end target
end subroutine adjust

end module repro_mod

program reproducer
  use repro_mod, only : adjust
  implicit none
  real :: x(8)
  x(:) = 1.0
  call adjust(x, 8)            ! OBC absent -> host SIGSEGV with ifx
  if (all(x == 2.0)) then
    print '(a)', 'PASS'
  else
    print '(a)', 'FAIL'
    error stop 1
  endif
end program reproducer
