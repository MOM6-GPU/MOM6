! ifx reproducer (needs a GPU): an offloaded loop over an assumed-shape dummy argument that is a
! NON-CONTIGUOUS section of a larger array (interior of an array with halos, as MOM6 passes
! array(isc:iec,jsc:jec) or h(:,:,k)) reads wrong values on the device.
!
! In MOM6, reproducing_sum(array(HI%isc:HI%iec,HI%jsc:HI%jec)) summed a 44x40 interior of a 52x48
! array on the device and lost the last 6 columns (an array of ones summed to 1496, not 1760):
! consistent with mapping only size(section) elements from the first one, instead of the strided
! extent, so the last (extent - size)/stride columns are not transferred.
!
!   ifx -O3 -qopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent reproducer.F90
module sum_mod
  implicit none
  private
  public :: dev_sum_dc, dev_sum_omp
contains
  !> Sum of an assumed-shape array on the device (do concurrent)
  real function dev_sum_dc(a) result(s)
    real, intent(in) :: a(:,:) !< Values [arbitrary]
    real :: t  ! Accumulator [arbitrary]
    integer :: i, j, n1, n2
    ! Bounds in locals: size(a,1) and size(a,2) as do concurrent bounds crash ifx (ICE #5633).
    n1 = size(a,1) ; n2 = size(a,2)
    t = 0.0
    do concurrent (j=1:n2, i=1:n1) reduce(+:t)
      t = t + a(i,j)
    enddo
    s = t
  end function dev_sum_dc
  !> Same with an explicit OpenMP target loop
  real function dev_sum_omp(a) result(s)
    real, intent(in) :: a(:,:) !< Values [arbitrary]
    real :: t  ! Accumulator [arbitrary]
    integer :: i, j
    t = 0.0
    !$omp target teams loop collapse(2) reduction(+:t) map(tofrom: t)
    do j=1,size(a,2) ; do i=1,size(a,1) ; t = t + a(i,j) ; enddo ; enddo
    s = t
  end function dev_sum_omp
end module sum_mod

program reproducer
  use sum_mod, only : dev_sum_dc, dev_sum_omp
  implicit none
  integer, parameter :: halo = 4, ni = 44, nj = 40
  real :: full(1-halo:ni+halo, 1-halo:nj+halo)   ! 52 x 48, like a MOM6 array with halos
  real :: contig(ni,nj), s_ref
  integer :: nfail
  full(:,:) = -1.0e6               ! halo values must never be summed
  full(1:ni,1:nj) = 1.0            ! interior: ones -> expected sum = ni*nj = 1760
  contig(:,:) = 1.0
  s_ref = real(ni*nj)
  nfail = 0
  call check('contiguous array          (do concurrent) ', dev_sum_dc(contig))
  call check('interior section full(1:ni,1:nj) (do conc.)', dev_sum_dc(full(1:ni,1:nj)))
  call check('interior section full(1:ni,1:nj) (omp)     ', dev_sum_omp(full(1:ni,1:nj)))
  if (nfail == 0) then ; print '(a)', 'PASS' ; else ; print '(a)', 'FAIL' ; error stop 1 ; endif
contains
  subroutine check(label, s)
    character(len=*), intent(in) :: label
    real, intent(in) :: s
    print '(a,a,f12.1,a,f8.1,a)', label, ': sum =', s, '  (expect', s_ref, ')'
    if (s /= s_ref) nfail = nfail + 1
  end subroutine check
end program reproducer
