! ifx reproducer (needs a GPU): what happens to a host structure's pointer components
! when an offloaded loop implicitly maps the structure.
!
! Compiler: ifx (IFX) 2026.1.0 20260617 (Aurora)
!   ifx -qopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent reproducer.F90
!
! MOM6 pattern: CS is not present on the device, and an offloaded do concurrent writes
! CS%arr(i).  CS is then implicitly mapped tofrom, so after the kernel the device copy is
! written back over the host CS.  In MOM6, pointer components of the host CS were null
! and their targets zeroed afterwards, and the next host use segfaulted.
!
! Each case prints whether the host pointer component and its target survived.
module repro_mod
  implicit none
  private
  public :: inner_t, cs_t, kernel_dc, kernel_omp

  !> A structure reached through a pointer component (like zlike_CS or EOS_type)
  type :: inner_t
    integer :: n = 0                 !< A scalar field
    real, allocatable :: r(:)        !< An allocatable field [arbitrary]
  end type inner_t

  !> A control structure like MOM_control_struct
  type :: cs_t
    real, allocatable :: arr(:)               !< Array written on the device [arbitrary]
    type(inner_t), pointer :: p => null()     !< Pointer component, only used on the host
    real :: scalar = 1.0                      !< A scalar field [arbitrary]
  end type cs_t

contains

!> Zero CS%arr in an offloaded do concurrent (implicit map of CS)
subroutine kernel_dc(CS, n)
  type(cs_t), intent(inout) :: CS !< Control structure
  integer,    intent(in)    :: n  !< Array size
  integer :: i
  do concurrent (i=1:n)
    CS%arr(i) = 0.0
  enddo
end subroutine kernel_dc

!> Zero CS%arr in an explicit target region (implicit map of CS)
subroutine kernel_omp(CS, n)
  type(cs_t), intent(inout) :: CS !< Control structure
  integer,    intent(in)    :: n  !< Array size
  integer :: i
  !$omp target teams distribute parallel do
  do i=1,n
    CS%arr(i) = 0.0
  enddo
end subroutine kernel_omp

end module repro_mod

program reproducer
  use repro_mod, only : cs_t, kernel_dc, kernel_omp
  implicit none
  integer, parameter :: n = 16
  integer :: nfail = 0

  call run_case('A: do concurrent, CS%arr entered, CS not present', 'dc', .false.)
  call run_case('B: do concurrent, after enter(to: CS) + exit(release: CS)', 'dc', .true.)
  call run_case('C: omp target, CS%arr entered, CS not present', 'omp', .false.)

  if (nfail == 0) then
    print '(a)', 'PASS'
  else
    print '(a,i0,a)', 'FAIL: ', nfail, ' case(s) corrupted the host structure'
    error stop 1
  endif

contains

  subroutine run_case(label, kind, enter_release)
    character(len=*), intent(in) :: label, kind
    logical, intent(in) :: enter_release
    type(cs_t), pointer :: CSp
    logical :: ok
    allocate(CSp)
    allocate(CSp%arr(n), source=1.0)
    allocate(CSp%p) ; CSp%p%n = 42 ; allocate(CSp%p%r(3), source=7.0)
    CSp%scalar = 3.0
    !$omp target enter data map(to: CSp%arr)
    if (enter_release) then
      !$omp target enter data map(to: CSp)
      !$omp target exit data map(release: CSp)
    endif
    if (kind == 'dc') then ; call kernel_dc(CSp, n) ; else ; call kernel_omp(CSp, n) ; endif
    !$omp target exit data map(from: CSp%arr)
    ok = associated(CSp%p)
    print '(a)', label
    print '(4x,a,l1)', 'host CS%p still associated: ', ok
    if (ok) then
      print '(4x,a,i0,a)', 'host CS%p%n = ', CSp%p%n, '   (expect 42)'
      if (allocated(CSp%p%r)) then
        print '(4x,a,f5.1,a)', 'host CS%p%r(1) = ', CSp%p%r(1), '   (expect 7.0)'
      else
        print '(4x,a)', 'host CS%p%r NOT allocated   (expect allocated)'
      endif
      ok = (CSp%p%n == 42)
      if (ok) ok = allocated(CSp%p%r)
      if (ok) ok = (CSp%p%r(1) == 7.0)
    endif
    print '(4x,a,f5.1,a,f5.1,a)', 'host CS%scalar = ', CSp%scalar, '   (expect 3.0); CS%arr(1) = ', &
          CSp%arr(1), ' (expect 0.0)'
    if (.not. ok) nfail = nfail + 1
  end subroutine run_case

end program reproducer
