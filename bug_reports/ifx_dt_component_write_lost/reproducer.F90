! ifx reproducer (needs a GPU): a kernel writes into allocatable components of a derived-type
! dummy argument whose components were mapped earlier with
!   !$omp target enter data map(to: visc%a, visc%b)
! and the values are then read back with  !$omp target update from(visc%a).
! Modeled on MOM6's set_viscous_BBL (MOM_set_viscosity.F90), where visc%bbl_thick_u and
! visc%Kv_bbl_u came back all zeros although the kernel computed the right values.
!
!   ifx -O3 -qopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent reproducer.F90
module visc_mod
  implicit none
  private
  public :: write_plain, write_guarded, write_dc
  !> A type like MOM6's vertvisc_type
  type, public :: visc_type
    real, allocatable :: a(:,:) !< First field [arbitrary]
    real, allocatable :: b(:,:) !< Second field [arbitrary]
    real, allocatable :: c(:,:) !< Never allocated [arbitrary]
  end type visc_type
contains
  !> A: plain write into visc%a inside an omp target teams loop
  subroutine write_plain(visc, n)
    type(visc_type), intent(inout) :: visc !< Fields
    integer, intent(in) :: n !< Size
    integer :: i, j
    !$omp target teams loop collapse(2)
    do j=1,n ; do i=1,n ; visc%a(i,j) = real(i+j) ; enddo ; enddo
  end subroutine write_plain
  !> B: like MOM6, the write to visc%b is guarded by allocated(), and an unallocated component exists
  subroutine write_guarded(visc, n)
    type(visc_type), intent(inout) :: visc !< Fields
    integer, intent(in) :: n !< Size
    integer :: i, j
    !$omp target teams loop collapse(2)
    do j=1,n ; do i=1,n
      visc%a(i,j) = real(i+j)
      if (allocated(visc%b)) visc%b(i,j) = real(i+j)
      if (allocated(visc%c)) visc%c(i,j) = real(i+j)
    enddo ; enddo
  end subroutine write_guarded
  !> C: same as A with do concurrent
  subroutine write_dc(visc, n)
    type(visc_type), intent(inout) :: visc !< Fields
    integer, intent(in) :: n !< Size
    integer :: i, j
    do concurrent (j=1:n, i=1:n)
      visc%a(i,j) = real(i+j)
    enddo
  end subroutine write_dc
end module visc_mod

program reproducer
  use visc_mod, only : visc_type, write_plain, write_guarded, write_dc
  implicit none
  integer, parameter :: n = 44
  type(visc_type), target :: visc_t      ! case 1: plain variable, components mapped after allocation
  type(visc_type), pointer :: pv => null() ! case 2: MOM6's order (see below)
  real :: ref
  integer :: nfail
  ref = real(n*n*(n+1))   ! sum over i,j of (i+j)
  nfail = 0

  print '(a)', '--- 1: plain variable; allocate components, then enter data map(to: v%a, v%b)'
  allocate(visc_t%a(n,n), source=0.0) ; allocate(visc_t%b(n,n), source=0.0)
  !$omp target enter data map(to: visc_t%a, visc_t%b)
  call run_cases(visc_t)

  print '(a)', '--- 2: MOM6 order: allocate(pv); enter data map(alloc: pv); update to(pv) while its'
  print '(a)', '       components are unallocated; THEN allocate components and map(to: pv%a, pv%b)'
  allocate(pv)
  !$omp target enter data map(alloc: pv)
  !$omp target update to(pv)
  allocate(pv%a(n,n), source=0.0) ; allocate(pv%b(n,n), source=0.0)
  !$omp target enter data map(to: pv%a, pv%b)
#ifdef WORKAROUND
  ! Refresh the whole device copy of pv now that its components are allocated and mapped: this
  ! sends the host descriptors (bounds, allocation status), and the runtime re-attaches the device
  ! addresses of the mapped components at every kernel launch.
  !$omp target update to(pv)
#endif
  call run_cases(pv)

  if (nfail == 0) then ; print '(a)', 'PASS' ; else ; print '(a,i0,a)', 'FAIL (', nfail, ' wrong)' ; error stop 1 ; endif
contains
  subroutine run_cases(v)
    type(visc_type), intent(inout) :: v
    call reset(v) ; call write_plain(v, n)   ; call report('A plain write to v%a           ', v)
    call reset(v) ; call write_guarded(v, n) ; call report('B allocated()-guarded, v%a     ', v)
    !$omp target update from(v%b)
    print '(a,f12.1,a,f12.1)', '   B, v%b after update from: sum =', sum(v%b), '  expect', ref
    if (sum(v%b) /= ref) nfail = nfail + 1
    call reset(v) ; call write_dc(v, n)      ; call report('C do concurrent write to v%a   ', v)
  end subroutine run_cases
  subroutine report(label, v)
    character(len=*), intent(in) :: label
    type(visc_type), intent(inout) :: v
    real :: host_sum
    host_sum = sum(v%a)                       ! host copy right after the kernel
    !$omp target update from(v%a)
    print '(a,a,f12.1,a,f12.1,a,f12.1)', label, ': host after kernel', host_sum, &
        ', after update from', sum(v%a), '  expect', ref
    if (sum(v%a) /= ref) nfail = nfail + 1
  end subroutine report
  subroutine reset(v)
    type(visc_type), intent(inout) :: v
    v%a(:,:) = 0.0 ; v%b(:,:) = 0.0
    !$omp target update to(v%a, v%b)
  end subroutine reset
end program reproducer
