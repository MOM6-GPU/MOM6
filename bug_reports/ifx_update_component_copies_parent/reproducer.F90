! ifx reproducer: `!$omp target update from(CS%arr)` / `to(CS%arr)`, where CS is a POINTER
! (or allocatable) to a derived type, transfers the WHOLE structure CS, not just CS%arr.
!
! Compiler: ifx (IFX) 2026.1.0 20260617 (Aurora)
!   ifx -qopenmp -fopenmp-targets=spir64 reproducer.F90
!
! Evidence without a GPU: the map-type table emitted for `update from(CS%arr)` with a
! pointer base is [0x2, 0x2] (whole CS "from" + arr "from").  For a non-pointer dummy
! it is [0x0, 0x2] (correct).  run.sh prints these tables from the assembly.
!
! On a GPU: host fields of CS that changed after CS was mapped are overwritten by the
! stale device copy.  In MOM6 this reset barotropic_CS%module_is_initialized to .false.
! ("btcalc: Module MOM_barotropic must be initialized before it is used.").
!
! -DWORKAROUND binds the component with `associate` first; then only arr is transferred.
module repro_mod
  implicit none
  private
  public :: cs_t, update_from

  !> A control structure
  type :: cs_t
    real, allocatable :: arr(:)   !< An array computed on the device [arbitrary]
    integer :: flag = 0           !< A host-only field
  end type cs_t

contains

!> Copy CS%arr back from the device
subroutine update_from(CS)
  type(cs_t), pointer :: CS !< Control structure
#ifdef WORKAROUND
  associate(arr => CS%arr)
  !$omp target update from(arr)
  end associate
#else
  !$omp target update from(CS%arr)
#endif
end subroutine update_from

end module repro_mod

program reproducer
  use repro_mod, only : cs_t, update_from
  implicit none
  type(cs_t), pointer :: CS
  integer :: i

  allocate(CS)
  allocate(CS%arr(8), source=0.0)
  CS%flag = 1
  !$omp target enter data map(to: CS)        ! device copy of CS has flag = 1
  !$omp target enter data map(to: CS%arr)

  CS%flag = 7                                ! host-only change after mapping

  !$omp target teams distribute parallel do
  do i=1,8
    CS%arr(i) = real(i)
  enddo

  call update_from(CS)

  print '(a,i0,a)', 'host CS%flag   = ', CS%flag, '   (expect 7; 1 means all of CS was copied back)'
  print '(a,f4.1,a)', 'host CS%arr(8) = ', CS%arr(8), '   (expect 8.0)'
  if (CS%flag == 7 .and. CS%arr(8) == 8.0) then
    print '(a)', 'PASS'
  else
    print '(a)', 'FAIL'
    error stop 1
  endif
end program reproducer
