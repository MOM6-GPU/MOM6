! ifx internal compiler error reproducer:
!   OpenMP mapping of an ARRAY of an EXTENDED derived type whose allocatable
!   component is declared in the extension.
!
! Compiler: ifx (IFX) 2026.1.0 20260617 (Aurora)
!
! Fails at compile time (both -O0 and -O3), with or without -fopenmp-targets:
!   ifx -qopenmp reproducer.F90
!   ifx -qopenmp -fopenmp-targets=spir64 reproducer.F90
!   -> error #5623: **Internal compiler error: internal abort**
!
! Compiles with -DWORKAROUND (ext_t no longer extends base_t).
!
! Every construct that maps such an object crashes: target update, target enter data,
! map clauses on target, and the implicit map of an offloaded do concurrent.
! It also crashes when the array is nested deep inside the mapped object, e.g.
! MOM6's MOM_control_struct%diag%remap_axes*(:)%piecemeal_3d%buffer(:).
module repro_mod
  implicit none
  private
  public :: ext_t

  !> An (empty) parent type
  type :: base_t
  end type base_t

#ifdef WORKAROUND
  !> The same type, without the extension
  type :: ext_t
#else
  !> A type extension that adds an allocatable component
  type, extends(base_t) :: ext_t
#endif
    real, allocatable :: f(:) !< Data [arbitrary]
  end type ext_t

end module repro_mod

program reproducer
  use repro_mod, only : ext_t
  implicit none
  type(ext_t), allocatable :: buf(:)
  integer :: n

  allocate(buf(3))
  do n=1,3
    allocate(buf(n)%f(4)) ; buf(n)%f(:) = real(n)
  enddo

  !$omp target enter data map(to: buf)    ! <-- triggers the ICE
  !$omp target exit data map(from: buf)

  if (all([(all(buf(n)%f(:) == real(n)), n=1,3)])) then
    print '(a)', 'PASS: data round-tripped'
  else
    print '(a)', 'FAIL: data changed'
    error stop 1
  endif
end program reproducer
