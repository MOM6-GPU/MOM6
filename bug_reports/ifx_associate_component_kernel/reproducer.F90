! Investigation (needs a GPU): reading an allocatable component of a pointer-based, already-mapped
! derived type inside an offloaded do concurrent, directly (G%a) vs through an associate name.
!
! In MOM6, replacing G%IareaT, G%dy_Cu, G%IdxT by associate names in zonal/meridional_flux_adjust
! changed the answers (day-1 energy 1.629E-03 -> 5.456E-05).  G there is a pointer (CS%G) whose
! allocatable components were mapped one by one with `enter data map(to: G%IareaT, ...)`.
!   ifx -O3 -qopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent reproducer.F90
module grid_mod
  implicit none
  private
  public :: grid_t
  !> Like ocean_grid_type: a scalar and several allocatable arrays
  type :: grid_t
    integer :: isc = 0, iec = 0                !< Index bounds
    real, allocatable :: IareaT(:,:)           !< Inverse cell area [arbitrary]
    real, allocatable :: dy_Cu(:,:)            !< Face length [arbitrary]
    real, allocatable :: other(:,:)            !< Not used by the kernels [arbitrary]
  end type grid_t
end module grid_mod

module kern_mod
  use grid_mod, only : grid_t
  implicit none
  private
  public :: via_component, via_associate
contains
  !> out(i,j) = IareaT*dy_Cu, referencing G%... in the kernel
  subroutine via_component(G, out, n)
    type(grid_t), intent(in) :: G      !< Grid (non-pointer dummy, like MOM6's routines)
    integer,      intent(in) :: n      !< Size
    real,      intent(inout) :: out(n,n) !< Result [arbitrary]
    integer :: i, j
    do concurrent (j=1:n, i=1:n)
      out(i,j) = G%IareaT(i,j) * G%dy_Cu(i,j)
    enddo
  end subroutine via_component
  !> Same, referencing associate names in the kernel
  subroutine via_associate(G, out, n)
    type(grid_t), intent(in) :: G      !< Grid
    integer,      intent(in) :: n      !< Size
    real,      intent(inout) :: out(n,n) !< Result [arbitrary]
    integer :: i, j
    associate(G_IareaT => G%IareaT, G_dy_Cu => G%dy_Cu)
    do concurrent (j=1:n, i=1:n)
      out(i,j) = G_IareaT(i,j) * G_dy_Cu(i,j)
    enddo
    end associate
  end subroutine via_associate
end module kern_mod

program reproducer
  use grid_mod, only : grid_t
  use kern_mod, only : via_component, via_associate
  implicit none
  integer, parameter :: n = 40
  type(grid_t), pointer :: G
  real :: a(n,n), b(n,n)
  allocate(G)
  allocate(G%IareaT(n,n), source=2.0) ; allocate(G%dy_Cu(n,n), source=3.0)
  allocate(G%other(n,n), source=-1.0)
  !$omp target enter data map(to: G%IareaT, G%dy_Cu)   ! like initialize_MOM, pointer base
  a(:,:) = 0.0 ; b(:,:) = 0.0
  !$omp target data map(tofrom: a, b)
  call via_component(G, a, n)
  call via_associate(G, b, n)
  !$omp end target data
  print '(a,2f8.3)', 'via G%comp   : out(1,1), out(n,n) =', a(1,1), a(n,n)
  print '(a,2f8.3)', 'via associate: out(1,1), out(n,n) =', b(1,1), b(n,n)
  if (all(a == 6.0) .and. all(b == 6.0)) then
    print '(a)', 'PASS'
  else
    print '(a)', 'FAIL (expect 6.0 everywhere)'
    error stop 1
  endif
end program reproducer
