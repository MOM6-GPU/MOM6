! ifx reproducer: `!$omp declare target` on a separate module procedure.
!
! Compiler: ifx (IFX) 2026.1.0 20260617 (Aurora)
!
! There is no placement of the directive that works for every caller:
!
!   default (interface and body, the conforming form):
!     compile error #8682: Multiple !$OMP DECLARE TARGET declarations.
!   -DIFACE_ONLY (directive only in the parent module's interface):
!     compiles and links, and callers offload and call f, but the submodule body is
!     never compiled for the device.  The device image then fails to load at run
!     time on the GPU ("Module link failed").
!   -DWORKAROUND (directive only in the submodule body):
!     the body is compiled for the device, and calls from explicit !$omp target
!     regions work.  But a `do concurrent` that calls f is not offloaded
!     (warning #5476), because callers don't see f as a device procedure.
!
! OpenMP's Fortran restrictions for declare target say a directive in an interface
! block must match one in the definition of the procedure, so the default form
! should be the conforming one.
module parent
  implicit none ; private
  public :: f

  interface
    !> Doubles x
    elemental module function f(x) result(a)
      real, intent(in) :: x !< Input [arbitrary]
      real :: a             !< 2*x [arbitrary]
#ifndef WORKAROUND
      !$omp declare target
#endif
    end function f
  end interface
end module parent

submodule (parent) child
  implicit none
contains
  module procedure f
#ifndef IFACE_ONLY
    !$omp declare target    ! <-- error #8682 when the interface also has it
#endif
    a = 2.0 * x
  end procedure f
end submodule child

program reproducer
  use parent, only : f
  implicit none
  real :: v(8)
  integer :: i

  v(:) = 1.0
  !$omp target teams distribute parallel do map(tofrom: v)
  do i = 1, 8
    v(i) = f(v(i))
  enddo

  if (all(v == 2.0)) then
    print '(a)', 'PASS: f evaluated correctly in the target region'
  else
    print '(a)', 'FAIL: wrong values'
    error stop 1
  endif
end program reproducer
