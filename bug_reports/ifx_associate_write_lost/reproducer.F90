! ifx reproducer: writes through an ASSOCIATE name inside a do concurrent that is offloaded with
! -fopenmp-target-do-concurrent.  Modeled on MOM6's step_MOM (MOM.F90), which accumulates
!   associate(ssh_rint => CS%ssh_rint)
!   do concurrent (j=js:je, i=is:ie) ; ssh_rint(i,j) = ssh_rint(i,j) + dt*ssh(i,j) ; enddo
!   end associate
! where CS is a pointer to a derived type with an allocatable component mapped with
! !$omp target enter data map(to: CS%ssh_rint).  ssh_rint stayed zero, on the GPU and also with
! OMP_TARGET_OFFLOAD=DISABLED, while the same code built without -qopenmp is correct.
!
!   ifx -O3 -qopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent reproducer.F90
module cs_mod
  implicit none
  !> A control structure like MOM_control_struct
  type, public :: cs_type
    real, allocatable :: ssh_rint(:,:) !< Running time integral [arbitrary]
  end type cs_type
end module cs_mod

program reproducer
  use cs_mod, only : cs_type
  implicit none
  integer, parameter :: n = 44
  type(cs_type), pointer :: CS => null()
  real, allocatable :: ssh(:,:)
  real :: dt, expect, got
  integer :: i, j, nfail

  allocate(CS)
  !$omp target enter data map(alloc: CS)
  allocate(CS%ssh_rint(n,n), source=0.0)
  !$omp target enter data map(to: CS%ssh_rint)
  !$omp target update to(CS)        ! as in MOM6 (with the ifx_dt_component_write_lost workaround)
  allocate(ssh(n,n), source=1.0)
  !$omp target enter data map(to: ssh)
  dt = 2.0 ; nfail = 0

  ! Reset and accumulate twice through an associate name, like step_MOM
  associate(ssh_rint => CS%ssh_rint)
  do concurrent (j=1:n, i=1:n) ; ssh_rint(i,j) = 0. ; enddo
  end associate
  associate(ssh_rint => CS%ssh_rint)
  do concurrent (j=1:n, i=1:n) ; ssh_rint(i,j) = ssh_rint(i,j) + dt * ssh(i,j) ; enddo
  end associate
  associate(ssh_rint => CS%ssh_rint)
  do concurrent (j=1:n, i=1:n) ; ssh_rint(i,j) = ssh_rint(i,j) + dt * ssh(i,j) ; enddo
  end associate
  !$omp target update from(CS%ssh_rint)
  expect = 2.0*dt*n*n ; got = sum(CS%ssh_rint)
  print '(a,f12.1,a,f12.1)', 'via associate name : sum =', got, '  expect', expect
  if (got /= expect) nfail = nfail + 1

  ! The same through CS% directly
  do concurrent (j=1:n, i=1:n) ; CS%ssh_rint(i,j) = 0. ; enddo
  do concurrent (j=1:n, i=1:n) ; CS%ssh_rint(i,j) = CS%ssh_rint(i,j) + dt * ssh(i,j) ; enddo
  do concurrent (j=1:n, i=1:n) ; CS%ssh_rint(i,j) = CS%ssh_rint(i,j) + dt * ssh(i,j) ; enddo
  !$omp target update from(CS%ssh_rint)
  got = sum(CS%ssh_rint)
  print '(a,f12.1,a,f12.1)', 'via CS%ssh_rint    : sum =', got, '  expect', expect
  if (got /= expect) nfail = nfail + 1

  ! Workaround candidates
  ! (a) keep the associate name but use an explicit OpenMP loop instead of do concurrent
  associate(ssh_rint => CS%ssh_rint)
  !$omp target teams loop collapse(2)
  do j=1,n ; do i=1,n ; ssh_rint(i,j) = 0. ; enddo ; enddo
  !$omp target teams loop collapse(2)
  do j=1,n ; do i=1,n ; ssh_rint(i,j) = ssh_rint(i,j) + 2.0*dt * ssh(i,j) ; enddo ; enddo
  end associate
  !$omp target update from(CS%ssh_rint)
  got = sum(CS%ssh_rint)
  print '(a,f12.1,a,f12.1)', 'WORKAROUND associate + omp loop : sum =', got, '  expect', expect
  if (got /= expect) nfail = nfail + 1
  ! (b) a pointer instead of the associate name
  block
    real, pointer :: p(:,:)
    p => CS%ssh_rint
    do concurrent (j=1:n, i=1:n) ; p(i,j) = 0. ; enddo
    do concurrent (j=1:n, i=1:n) ; p(i,j) = p(i,j) + 2.0*dt * ssh(i,j) ; enddo
  end block
  !$omp target update from(CS%ssh_rint)
  got = sum(CS%ssh_rint)
  print '(a,f12.1,a,f12.1)', 'WORKAROUND pointer + do conc.   : sum =', got, '  expect', expect
  if (got /= expect) nfail = nfail + 1

  if (nfail == 0) then ; print '(a)', 'PASS' ; else ; print '(a)', 'FAIL' ; error stop 1 ; endif
end program reproducer
