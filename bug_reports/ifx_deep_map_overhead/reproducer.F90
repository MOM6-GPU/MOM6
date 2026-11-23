!> Reproducer: the cost of launching a kernel grows with the number of allocatable
!! components of every derived-type object the kernel references, even when the object and
!! all its components are already present on the device and the kernel uses only one of them.
!!
!! Each structure (1, 25 or 100 allocatable components of size n) is mapped once with
!! "target enter data".  The same one-component kernel, a(i) = a(i) + 1, is then launched
!! nlaunch times in each variant and the time per launch is printed.
!!
!! Generated: the component lists are written out in full.
program deep_map_overhead
  use omp_lib, only : omp_get_wtime
  implicit none
  integer, parameter :: n = 4096      !< Component length
  integer, parameter :: nlaunch = 2000 !< Launches timed per variant
  !> A structure with 1 allocatable components
  type :: t1_t
    integer :: isc = 1
    real, allocatable :: a001(:)
  end type t1_t
  !> A structure with 25 allocatable components
  type :: t25_t
    integer :: isc = 1
    real, allocatable :: a001(:)
    real, allocatable :: a002(:)
    real, allocatable :: a003(:)
    real, allocatable :: a004(:)
    real, allocatable :: a005(:)
    real, allocatable :: a006(:)
    real, allocatable :: a007(:)
    real, allocatable :: a008(:)
    real, allocatable :: a009(:)
    real, allocatable :: a010(:)
    real, allocatable :: a011(:)
    real, allocatable :: a012(:)
    real, allocatable :: a013(:)
    real, allocatable :: a014(:)
    real, allocatable :: a015(:)
    real, allocatable :: a016(:)
    real, allocatable :: a017(:)
    real, allocatable :: a018(:)
    real, allocatable :: a019(:)
    real, allocatable :: a020(:)
    real, allocatable :: a021(:)
    real, allocatable :: a022(:)
    real, allocatable :: a023(:)
    real, allocatable :: a024(:)
    real, allocatable :: a025(:)
  end type t25_t
  !> A structure with 100 allocatable components
  type :: t100_t
    integer :: isc = 1
    real, allocatable :: a001(:)
    real, allocatable :: a002(:)
    real, allocatable :: a003(:)
    real, allocatable :: a004(:)
    real, allocatable :: a005(:)
    real, allocatable :: a006(:)
    real, allocatable :: a007(:)
    real, allocatable :: a008(:)
    real, allocatable :: a009(:)
    real, allocatable :: a010(:)
    real, allocatable :: a011(:)
    real, allocatable :: a012(:)
    real, allocatable :: a013(:)
    real, allocatable :: a014(:)
    real, allocatable :: a015(:)
    real, allocatable :: a016(:)
    real, allocatable :: a017(:)
    real, allocatable :: a018(:)
    real, allocatable :: a019(:)
    real, allocatable :: a020(:)
    real, allocatable :: a021(:)
    real, allocatable :: a022(:)
    real, allocatable :: a023(:)
    real, allocatable :: a024(:)
    real, allocatable :: a025(:)
    real, allocatable :: a026(:)
    real, allocatable :: a027(:)
    real, allocatable :: a028(:)
    real, allocatable :: a029(:)
    real, allocatable :: a030(:)
    real, allocatable :: a031(:)
    real, allocatable :: a032(:)
    real, allocatable :: a033(:)
    real, allocatable :: a034(:)
    real, allocatable :: a035(:)
    real, allocatable :: a036(:)
    real, allocatable :: a037(:)
    real, allocatable :: a038(:)
    real, allocatable :: a039(:)
    real, allocatable :: a040(:)
    real, allocatable :: a041(:)
    real, allocatable :: a042(:)
    real, allocatable :: a043(:)
    real, allocatable :: a044(:)
    real, allocatable :: a045(:)
    real, allocatable :: a046(:)
    real, allocatable :: a047(:)
    real, allocatable :: a048(:)
    real, allocatable :: a049(:)
    real, allocatable :: a050(:)
    real, allocatable :: a051(:)
    real, allocatable :: a052(:)
    real, allocatable :: a053(:)
    real, allocatable :: a054(:)
    real, allocatable :: a055(:)
    real, allocatable :: a056(:)
    real, allocatable :: a057(:)
    real, allocatable :: a058(:)
    real, allocatable :: a059(:)
    real, allocatable :: a060(:)
    real, allocatable :: a061(:)
    real, allocatable :: a062(:)
    real, allocatable :: a063(:)
    real, allocatable :: a064(:)
    real, allocatable :: a065(:)
    real, allocatable :: a066(:)
    real, allocatable :: a067(:)
    real, allocatable :: a068(:)
    real, allocatable :: a069(:)
    real, allocatable :: a070(:)
    real, allocatable :: a071(:)
    real, allocatable :: a072(:)
    real, allocatable :: a073(:)
    real, allocatable :: a074(:)
    real, allocatable :: a075(:)
    real, allocatable :: a076(:)
    real, allocatable :: a077(:)
    real, allocatable :: a078(:)
    real, allocatable :: a079(:)
    real, allocatable :: a080(:)
    real, allocatable :: a081(:)
    real, allocatable :: a082(:)
    real, allocatable :: a083(:)
    real, allocatable :: a084(:)
    real, allocatable :: a085(:)
    real, allocatable :: a086(:)
    real, allocatable :: a087(:)
    real, allocatable :: a088(:)
    real, allocatable :: a089(:)
    real, allocatable :: a090(:)
    real, allocatable :: a091(:)
    real, allocatable :: a092(:)
    real, allocatable :: a093(:)
    real, allocatable :: a094(:)
    real, allocatable :: a095(:)
    real, allocatable :: a096(:)
    real, allocatable :: a097(:)
    real, allocatable :: a098(:)
    real, allocatable :: a099(:)
    real, allocatable :: a100(:)
  end type t100_t

  type(t1_t)   :: s1
  type(t25_t)  :: s25
  type(t100_t) :: s100
  integer :: i, it, nvar_s100
  real(kind=8) :: t0
  logical :: ok

  allocate(s1%a001(n)) ; s1%a001(:) = 0.0
  allocate(s25%a001(n)) ; s25%a001(:) = 0.0
  allocate(s25%a002(n)) ; s25%a002(:) = 0.0
  allocate(s25%a003(n)) ; s25%a003(:) = 0.0
  allocate(s25%a004(n)) ; s25%a004(:) = 0.0
  allocate(s25%a005(n)) ; s25%a005(:) = 0.0
  allocate(s25%a006(n)) ; s25%a006(:) = 0.0
  allocate(s25%a007(n)) ; s25%a007(:) = 0.0
  allocate(s25%a008(n)) ; s25%a008(:) = 0.0
  allocate(s25%a009(n)) ; s25%a009(:) = 0.0
  allocate(s25%a010(n)) ; s25%a010(:) = 0.0
  allocate(s25%a011(n)) ; s25%a011(:) = 0.0
  allocate(s25%a012(n)) ; s25%a012(:) = 0.0
  allocate(s25%a013(n)) ; s25%a013(:) = 0.0
  allocate(s25%a014(n)) ; s25%a014(:) = 0.0
  allocate(s25%a015(n)) ; s25%a015(:) = 0.0
  allocate(s25%a016(n)) ; s25%a016(:) = 0.0
  allocate(s25%a017(n)) ; s25%a017(:) = 0.0
  allocate(s25%a018(n)) ; s25%a018(:) = 0.0
  allocate(s25%a019(n)) ; s25%a019(:) = 0.0
  allocate(s25%a020(n)) ; s25%a020(:) = 0.0
  allocate(s25%a021(n)) ; s25%a021(:) = 0.0
  allocate(s25%a022(n)) ; s25%a022(:) = 0.0
  allocate(s25%a023(n)) ; s25%a023(:) = 0.0
  allocate(s25%a024(n)) ; s25%a024(:) = 0.0
  allocate(s25%a025(n)) ; s25%a025(:) = 0.0
  allocate(s100%a001(n)) ; s100%a001(:) = 0.0
  allocate(s100%a002(n)) ; s100%a002(:) = 0.0
  allocate(s100%a003(n)) ; s100%a003(:) = 0.0
  allocate(s100%a004(n)) ; s100%a004(:) = 0.0
  allocate(s100%a005(n)) ; s100%a005(:) = 0.0
  allocate(s100%a006(n)) ; s100%a006(:) = 0.0
  allocate(s100%a007(n)) ; s100%a007(:) = 0.0
  allocate(s100%a008(n)) ; s100%a008(:) = 0.0
  allocate(s100%a009(n)) ; s100%a009(:) = 0.0
  allocate(s100%a010(n)) ; s100%a010(:) = 0.0
  allocate(s100%a011(n)) ; s100%a011(:) = 0.0
  allocate(s100%a012(n)) ; s100%a012(:) = 0.0
  allocate(s100%a013(n)) ; s100%a013(:) = 0.0
  allocate(s100%a014(n)) ; s100%a014(:) = 0.0
  allocate(s100%a015(n)) ; s100%a015(:) = 0.0
  allocate(s100%a016(n)) ; s100%a016(:) = 0.0
  allocate(s100%a017(n)) ; s100%a017(:) = 0.0
  allocate(s100%a018(n)) ; s100%a018(:) = 0.0
  allocate(s100%a019(n)) ; s100%a019(:) = 0.0
  allocate(s100%a020(n)) ; s100%a020(:) = 0.0
  allocate(s100%a021(n)) ; s100%a021(:) = 0.0
  allocate(s100%a022(n)) ; s100%a022(:) = 0.0
  allocate(s100%a023(n)) ; s100%a023(:) = 0.0
  allocate(s100%a024(n)) ; s100%a024(:) = 0.0
  allocate(s100%a025(n)) ; s100%a025(:) = 0.0
  allocate(s100%a026(n)) ; s100%a026(:) = 0.0
  allocate(s100%a027(n)) ; s100%a027(:) = 0.0
  allocate(s100%a028(n)) ; s100%a028(:) = 0.0
  allocate(s100%a029(n)) ; s100%a029(:) = 0.0
  allocate(s100%a030(n)) ; s100%a030(:) = 0.0
  allocate(s100%a031(n)) ; s100%a031(:) = 0.0
  allocate(s100%a032(n)) ; s100%a032(:) = 0.0
  allocate(s100%a033(n)) ; s100%a033(:) = 0.0
  allocate(s100%a034(n)) ; s100%a034(:) = 0.0
  allocate(s100%a035(n)) ; s100%a035(:) = 0.0
  allocate(s100%a036(n)) ; s100%a036(:) = 0.0
  allocate(s100%a037(n)) ; s100%a037(:) = 0.0
  allocate(s100%a038(n)) ; s100%a038(:) = 0.0
  allocate(s100%a039(n)) ; s100%a039(:) = 0.0
  allocate(s100%a040(n)) ; s100%a040(:) = 0.0
  allocate(s100%a041(n)) ; s100%a041(:) = 0.0
  allocate(s100%a042(n)) ; s100%a042(:) = 0.0
  allocate(s100%a043(n)) ; s100%a043(:) = 0.0
  allocate(s100%a044(n)) ; s100%a044(:) = 0.0
  allocate(s100%a045(n)) ; s100%a045(:) = 0.0
  allocate(s100%a046(n)) ; s100%a046(:) = 0.0
  allocate(s100%a047(n)) ; s100%a047(:) = 0.0
  allocate(s100%a048(n)) ; s100%a048(:) = 0.0
  allocate(s100%a049(n)) ; s100%a049(:) = 0.0
  allocate(s100%a050(n)) ; s100%a050(:) = 0.0
  allocate(s100%a051(n)) ; s100%a051(:) = 0.0
  allocate(s100%a052(n)) ; s100%a052(:) = 0.0
  allocate(s100%a053(n)) ; s100%a053(:) = 0.0
  allocate(s100%a054(n)) ; s100%a054(:) = 0.0
  allocate(s100%a055(n)) ; s100%a055(:) = 0.0
  allocate(s100%a056(n)) ; s100%a056(:) = 0.0
  allocate(s100%a057(n)) ; s100%a057(:) = 0.0
  allocate(s100%a058(n)) ; s100%a058(:) = 0.0
  allocate(s100%a059(n)) ; s100%a059(:) = 0.0
  allocate(s100%a060(n)) ; s100%a060(:) = 0.0
  allocate(s100%a061(n)) ; s100%a061(:) = 0.0
  allocate(s100%a062(n)) ; s100%a062(:) = 0.0
  allocate(s100%a063(n)) ; s100%a063(:) = 0.0
  allocate(s100%a064(n)) ; s100%a064(:) = 0.0
  allocate(s100%a065(n)) ; s100%a065(:) = 0.0
  allocate(s100%a066(n)) ; s100%a066(:) = 0.0
  allocate(s100%a067(n)) ; s100%a067(:) = 0.0
  allocate(s100%a068(n)) ; s100%a068(:) = 0.0
  allocate(s100%a069(n)) ; s100%a069(:) = 0.0
  allocate(s100%a070(n)) ; s100%a070(:) = 0.0
  allocate(s100%a071(n)) ; s100%a071(:) = 0.0
  allocate(s100%a072(n)) ; s100%a072(:) = 0.0
  allocate(s100%a073(n)) ; s100%a073(:) = 0.0
  allocate(s100%a074(n)) ; s100%a074(:) = 0.0
  allocate(s100%a075(n)) ; s100%a075(:) = 0.0
  allocate(s100%a076(n)) ; s100%a076(:) = 0.0
  allocate(s100%a077(n)) ; s100%a077(:) = 0.0
  allocate(s100%a078(n)) ; s100%a078(:) = 0.0
  allocate(s100%a079(n)) ; s100%a079(:) = 0.0
  allocate(s100%a080(n)) ; s100%a080(:) = 0.0
  allocate(s100%a081(n)) ; s100%a081(:) = 0.0
  allocate(s100%a082(n)) ; s100%a082(:) = 0.0
  allocate(s100%a083(n)) ; s100%a083(:) = 0.0
  allocate(s100%a084(n)) ; s100%a084(:) = 0.0
  allocate(s100%a085(n)) ; s100%a085(:) = 0.0
  allocate(s100%a086(n)) ; s100%a086(:) = 0.0
  allocate(s100%a087(n)) ; s100%a087(:) = 0.0
  allocate(s100%a088(n)) ; s100%a088(:) = 0.0
  allocate(s100%a089(n)) ; s100%a089(:) = 0.0
  allocate(s100%a090(n)) ; s100%a090(:) = 0.0
  allocate(s100%a091(n)) ; s100%a091(:) = 0.0
  allocate(s100%a092(n)) ; s100%a092(:) = 0.0
  allocate(s100%a093(n)) ; s100%a093(:) = 0.0
  allocate(s100%a094(n)) ; s100%a094(:) = 0.0
  allocate(s100%a095(n)) ; s100%a095(:) = 0.0
  allocate(s100%a096(n)) ; s100%a096(:) = 0.0
  allocate(s100%a097(n)) ; s100%a097(:) = 0.0
  allocate(s100%a098(n)) ; s100%a098(:) = 0.0
  allocate(s100%a099(n)) ; s100%a099(:) = 0.0
  allocate(s100%a100(n)) ; s100%a100(:) = 0.0
  !$omp target enter data map(to: s1, s25, s100)

  print '(a)', "Implicit map of the structure (current behaviour):"
  t0 = omp_get_wtime()
  do it = 1, nlaunch
    do concurrent (i=1:n)
      s1%a001(i) = s1%a001(i) + 1.0
    enddo
  enddo
  call report("  do concurrent, 1 allocatable component", t0)
  t0 = omp_get_wtime()
  do it = 1, nlaunch
    do concurrent (i=1:n)
      s25%a001(i) = s25%a001(i) + 1.0
    enddo
  enddo
  call report("  do concurrent, 25 allocatable components", t0)
  t0 = omp_get_wtime()
  do it = 1, nlaunch
    do concurrent (i=1:n)
      s100%a001(i) = s100%a001(i) + 1.0
    enddo
  enddo
  call report("  do concurrent, 100 allocatable components", t0)

  t0 = omp_get_wtime()
  do it = 1, nlaunch
    !$omp target teams loop
    do i = 1, n
      s100%a001(i) = s100%a001(i) + 1.0
    enddo
  enddo
  call report("  target teams loop, 100 allocatable components", t0)

  print '(a)', "Same kernel, 100 components, without the implicit map of the structure:"
  t0 = omp_get_wtime()
  do it = 1, nlaunch
    !$omp target teams loop map(present, tofrom: s100%a001)
    do i = 1, n
      s100%a001(i) = s100%a001(i) + 1.0
    enddo
  enddo
  call report("  target teams loop map(present, tofrom: s%a001)", t0)

  t0 = omp_get_wtime()
  do it = 1, nlaunch
    call kern_arg(s100%a001, n)
  enddo
  call report("  do concurrent on s%a001 passed as an argument", t0)
  nvar_s100 = 4

  !$omp target exit data map(from: s1, s25, s100)
  ok = all(s1%a001 == real(nlaunch)) .and. all(s25%a001 == real(nlaunch)) .and. &
       all(s100%a001 == real(nvar_s100*nlaunch))
  if (ok) then ; print '(a)', "results: PASS" ; else ; print '(a)', "results: FAIL" ; endif

contains

  !> The kernel on a plain array argument
  subroutine kern_arg(a, m)
    integer, intent(in) :: m        !< Array length
    real, intent(inout) :: a(m)     !< The array to increment
    integer :: j
    do concurrent (j=1:m)
      a(j) = a(j) + 1.0
    enddo
  end subroutine kern_arg

  !> Print the mean time per launch since tstart
  subroutine report(label, tstart)
    character(len=*), intent(in) :: label   !< Variant name
    real(kind=8),     intent(in) :: tstart  !< Start time [s]
    print '(a,t58,f8.1,a)', label, 1.0d6*(omp_get_wtime() - tstart)/nlaunch, " us/launch"
  end subroutine report

end program deep_map_overhead
