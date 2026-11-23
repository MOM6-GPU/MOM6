! ifx internal compiler error reproducer:
!   `do concurrent` offloaded via -fopenmp-target-do-concurrent, where two or
!   more index ranges take their bounds from components of the SAME
!   derived-type object.
!
! Compiler: ifx (IFX) 2026.1.0 20260617 (Aurora)
!
! Fails at compile time (both -O0 and -O3), in the spir64 device compile:
!   ifx -qopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent reproducer.F90
!   -> error #5633: **Internal compiler error: segmentation violation signal raised**
!
! Compiles and runs correctly:
!   - host only (no -fopenmp-targets=spir64)
!   - with -DWORKAROUND (bounds copied to local integers first)
!
! Other variants that compile (see README.md):
!   - only ONE index range uses a component of the derived type
!   - the ranges use components of two DIFFERENT objects (j=1:c%n, i=1:b%n)
!   - the equivalent "!$omp target teams loop collapse(2)" with b%n, b%m bounds
module repro_mod
  implicit none
  private
  public :: bounds_t, fill

  !> Container for loop bounds, analogous to MOM6's hor_index_type / ocean_grid_type
  type :: bounds_t
    integer :: n !< Extent of the first index
    integer :: m !< Extent of the second index
  end type bounds_t

contains

!> Fill a with a value inside a do concurrent whose bounds come from b
subroutine fill(b, a, val)
  type(bounds_t), intent(in)  :: b      !< Loop bounds
  real,           intent(out) :: a(:,:) !< Array to fill [arbitrary]
  real,           intent(in)  :: val    !< Fill value [arbitrary]
  integer :: i, j
#ifdef WORKAROUND
  integer :: n, m
  n = b%n ; m = b%m
  do concurrent (j=1:m, i=1:n)
#else
  do concurrent (j=1:b%m, i=1:b%n)   ! <-- triggers the ICE
#endif
    a(i,j) = val
  end do
end subroutine fill

end module repro_mod

program reproducer
  use repro_mod, only : bounds_t, fill
  implicit none
  type(bounds_t) :: b
  real, allocatable :: a(:,:)

  b = bounds_t(n=64, m=32)
  allocate(a(b%n, b%m))
  a = -1.0

  !$omp target data map(tofrom: a)
  call fill(b, a, 3.0)
  !$omp end target data

  if (all(a == 3.0)) then
    print '(a)', 'PASS: all elements set'
  else
    print '(a,i0,a)', 'FAIL: ', count(a /= 3.0), ' elements not set'
    error stop 1
  endif
end program reproducer
