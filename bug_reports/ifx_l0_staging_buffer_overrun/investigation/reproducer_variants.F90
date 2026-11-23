! Intel OpenMP offload (Level Zero) reproducer: after `!$omp target update to(CS)` of a
! structure with allocatable components, scalar components are wrong on the device.
!
! Compiler/runtime: ifx (IFX) 2026.1.0 20260617, Aurora (PVC), Level Zero plugin
!   ifx -O3 -qopenmp -fopenmp-targets=spir64 reproducer.F90
!   ifx -O3 -qopenmp -fopenmp-targets=spir64 -DALLOC_UPDATE_MAP -DPARENT_MANY reproducer.F90
!
! Expected: every kernel read gives bebt = 0.2, scale = 1.0, frac = 0.9.
! Observed: the scalars hold the data of other transfers of the same update (device
! addresses, or the value of the scalar submitted 64 transfers later).  In MOM6 all three
! read back as -5.829E+303, the bit pattern of a device address.  It goes away with
! LIBOMPTARGET_LEVEL_ZERO_COMMAND_MODE=sync, with LIBOMPTARGET_LEVEL_ZERO_STAGING_BUFFER_SIZE=0
! and with LIBOMPTARGET_DEBUG=1 (which slows the host down).  See README.md.
!
! A `target update` without `nowait` must complete before the next construct starts.
!
! Optional ingredients, to find the trigger:
!   -DNO_PARENT      child is a standalone allocated object, not a component of a parent
!   -DNO_ALLOCS      child has no allocatable components (no descriptor fix-ups)
!   -DNO_PAD         child has no large fixed-size padding (small struct)
!   -DWORKAROUND     a trivial `!$omp target` region (waits) between the update and the kernel
!   -DUPDATE_FIRST   candidate fix: update the whole structure before mapping its components
!   -DSCALAR_UPDATE  candidate fix: update only the scalar components instead of the structure
!   -DALLOC_UPDATE_MAP  MOM6 order: allocate components, update the structure, then map them
!   -DALLOC_SCALAR_MAP  MOM6 order, but the update covers only the scalar components
!   -DPARENT_ALLOCS  the parent also has 10 allocatable components, mapped before the child init
!   -DPARENT_MANY    the parent has 60 such components instead of 10
!   -DNPAR=<n>       the parent has n allocatable arrays (in an array of structures), mapped before
!                    the child init
!   -DNSIZE=<n>      the allocatable components are n x n default reals (default 64, 16 KiB)
!   -DBYTE_UPDATE    workaround for the MOM6 order: update the structure through a byte array
!   -DSCAN           also compare the whole padding on the device with the host (only for
!                    variants that update the whole structure)
!   -DNESTED         the child holds a nested structure (by value) with allocatable components
!   -DPOINTERS       the child has pointer components to host-only (never mapped) objects
module race_mod
  implicit none
  private
  public :: parent_t, child_t, NALLOC, NPAD, host_obj_t

  integer, parameter :: NALLOC = 60   !< Number of allocatable array components
  integer, parameter :: NPAD = 36000  !< Padding (reals), about 288 KB, like FMS group_pass_type

  !> Like MOM6's BT_OBC_type: a nested structure with allocatable components
  type :: nested_t
    real, allocatable :: n1(:,:), n2(:,:), n3(:,:), n4(:,:)
    integer :: k = 0
  end type nested_t

  !> A host-only object reached through a pointer component (like time_type, diag_ctrl)
  type :: host_obj_t
    real :: x(100) = 1.0
  end type host_obj_t

  !> Like MOM6's barotropic_CS
  type :: child_t
#ifdef NESTED
    type(nested_t) :: obc        !< Nested structure stored by value
#endif
#ifdef POINTERS
    type(host_obj_t), pointer :: time => null()  !< Pointers to host-only objects, never mapped
    type(host_obj_t), pointer :: diag => null()
#endif
#ifndef NO_ALLOCS
    real, allocatable :: a01(:,:), a02(:,:), a03(:,:), a04(:,:), a05(:,:), a06(:,:), a07(:,:), &
      a08(:,:), a09(:,:), a10(:,:), a11(:,:), a12(:,:), a13(:,:), a14(:,:), a15(:,:), a16(:,:), &
      a17(:,:), a18(:,:), a19(:,:), a20(:,:), a21(:,:), a22(:,:), a23(:,:), a24(:,:), a25(:,:), &
      a26(:,:), a27(:,:), a28(:,:), a29(:,:), a30(:,:), a31(:,:), a32(:,:), a33(:,:), a34(:,:), &
      a35(:,:), a36(:,:), a37(:,:), a38(:,:), a39(:,:), a40(:,:), a41(:,:), a42(:,:), a43(:,:), &
      a44(:,:), a45(:,:), a46(:,:), a47(:,:), a48(:,:), a49(:,:), a50(:,:), a51(:,:), a52(:,:), &
      a53(:,:), a54(:,:), a55(:,:), a56(:,:), a57(:,:), a58(:,:), a59(:,:), a60(:,:)
#endif
#ifndef NO_PAD
    real :: pad(NPAD) = 0.0  !< Stands in for embedded FMS group_pass_type components
#endif
    real :: dtbt_fraction = -1.0  !< Scalars read on the device
    real :: bebt = -1.0
    real :: BT_Coriolis_scale = -1.0
    logical :: initialized = .false.
  end type child_t

  !> A structure with one allocatable array
  type :: holder_t
    real, allocatable :: a(:,:)
  end type holder_t

  !> Like MOM6's MOM_dyn_split_RK2_CS, which holds barotropic_CS by value
  type :: parent_t
#ifdef NPAR
    type(holder_t) :: ph(NPAR)  !< NPAR more allocatable arrays, mapped before the child init
#endif
#if defined(PARENT_ALLOCS) || defined(PARENT_MANY)
    real, allocatable :: p01(:,:), p02(:,:), p03(:,:), p04(:,:), p05(:,:), p06(:,:), p07(:,:), &
      p08(:,:), p09(:,:), p10(:,:)  !< Like MOM_dyn_split_RK2_CS's own arrays (eta, u_av, ...)
#endif
#ifdef PARENT_MANY
    real, allocatable :: p11(:,:), p12(:,:), p13(:,:), p14(:,:), p15(:,:), p16(:,:), p17(:,:), p18(:,:), p19(:,:), p20(:,:), &
      p21(:,:), p22(:,:), p23(:,:), p24(:,:), p25(:,:), p26(:,:), p27(:,:), p28(:,:), p29(:,:), p30(:,:), &
      p31(:,:), p32(:,:), p33(:,:), p34(:,:), p35(:,:), p36(:,:), p37(:,:), p38(:,:), p39(:,:), p40(:,:), &
      p41(:,:), p42(:,:), p43(:,:), p44(:,:), p45(:,:), p46(:,:), p47(:,:), p48(:,:), p49(:,:), p50(:,:), &
      p51(:,:), p52(:,:), p53(:,:), p54(:,:), p55(:,:), p56(:,:), p57(:,:), p58(:,:), p59(:,:), p60(:,:)
#endif
    real :: head(30000) = 0.0
    type(child_t) :: child
    real :: tail(1000) = 0.0
  end type parent_t

end module race_mod

module init_mod
  use, intrinsic :: iso_c_binding, only : c_loc, c_f_pointer, c_int8_t
  use race_mod, only : child_t, NALLOC, NPAD
  implicit none
  private
  public :: child_init
contains

!> Like barotropic_init: allocate and map components, set scalars, update, use at once
subroutine child_init(CS, n, vals)
  type(child_t), target, intent(inout) :: CS !< Child structure, already mapped with map(alloc:)
  integer,       intent(in)    :: n       !< Array size
  real,          intent(out)   :: vals(3) !< bebt, scale, frac as read on the device
  integer(kind=c_int8_t), pointer :: CS_bytes(:) ! The storage of CS as bytes
#ifdef SCAN
  real, allocatable :: padcopy(:)   ! The device copy of CS%pad
  integer :: i, nbad, ifirst, ilast
  integer, save :: nprint = 0       ! The number of scan reports printed so far
#endif

#if defined(ALLOC_UPDATE_MAP) || defined(ALLOC_SCALAR_MAP)
  ! MOM6 barotropic_init order: components allocated on the host first, structure updated,
  ! components mapped afterwards.
  call alloc_only(CS, n)
#ifdef NESTED
  allocate(CS%obc%n1(n,n), CS%obc%n2(n,n), CS%obc%n3(n,n), CS%obc%n4(n,n))
#endif
#ifdef POINTERS
  allocate(CS%time, CS%diag)
#endif
  CS%bebt = 0.2 ; CS%BT_Coriolis_scale = 1.0 ; CS%dtbt_fraction = 0.9
#ifdef SCAN
  do i=1,NPAD ; CS%pad(i) = real(i) ; enddo
#endif
  CS%initialized = .true.
#if defined(ALLOC_SCALAR_MAP)
  !$omp target update to(CS%bebt, CS%BT_Coriolis_scale, CS%dtbt_fraction, CS%initialized)
#elif defined(BYTE_UPDATE)
  ! Workaround: update the structure through a byte array that shares its storage.  This is
  ! one map entry (one large copy), not one entry per component.
  call c_f_pointer(c_loc(CS), CS_bytes, [storage_size(CS)/8])
  !$omp target update to(CS_bytes)
#else
  !$omp target update to(CS)
#endif
  call map_only(CS)
#elif defined(UPDATE_FIRST)
  ! Candidate workaround: update the whole structure BEFORE mapping its allocatable components.
  CS%bebt = 0.2 ; CS%BT_Coriolis_scale = 1.0 ; CS%dtbt_fraction = 0.9
#ifdef SCAN
  do i=1,NPAD ; CS%pad(i) = real(i) ; enddo
#endif
  CS%initialized = .true.
  !$omp target update to(CS)
#ifndef NO_ALLOCS
  call alloc_map(CS, n)
#endif
#else
#ifndef NO_ALLOCS
  call alloc_map(CS, n)
#endif
  CS%bebt = 0.2 ; CS%BT_Coriolis_scale = 1.0 ; CS%dtbt_fraction = 0.9
#ifdef SCAN
  do i=1,NPAD ; CS%pad(i) = real(i) ; enddo
#endif
  CS%initialized = .true.

#ifdef SCALAR_UPDATE
  ! Candidate workaround: update only the scalar components that kernels read.
  !$omp target update to(CS%bebt, CS%BT_Coriolis_scale, CS%dtbt_fraction, CS%initialized)
#else
  !$omp target update to(CS)
#endif
#endif

#ifdef WORKAROUND
  !$omp target
  !$omp end target
#endif

  vals(:) = -7.0
  !$omp target map(from: vals)
  vals(1) = CS%bebt ; vals(2) = CS%BT_Coriolis_scale ; vals(3) = CS%dtbt_fraction
  !$omp end target

#ifdef SCAN
  ! Copy the whole padding back through a kernel, and report which part of the device
  ! structure differs from the host structure.
  allocate(padcopy(NPAD), source=-7.0)
  !$omp target map(from: padcopy)
  padcopy(:) = CS%pad(:)
  !$omp end target
  nbad = 0 ; ifirst = 0 ; ilast = 0
  do i=1,NPAD ; if (padcopy(i) /= real(i)) then
    nbad = nbad + 1 ; ilast = i ; if (ifirst == 0) ifirst = i
  endif ; enddo
  if ((nbad > 0) .and. (nprint < 4)) then
    nprint = nprint + 1
    print '(a,i0,a,i0,a,i0,a,i0)', '  scan: ', nbad, ' of ', NPAD, ' padding words differ, first ', ifirst, &
        ', last ', ilast
    print '(a,4(1x,z16.16))', '  scan: first wrong words (hex)', padcopy(ifirst:min(ifirst+3,NPAD))
    print '(a,3(1x,z16.16))', '  scan: scalars read (hex)     ', vals(1:3)
  endif
  deallocate(padcopy)
#endif
end subroutine child_init

#ifndef NO_ALLOCS
!> Allocate every allocatable component and map its data
subroutine alloc_map(CS, n)
  type(child_t), intent(inout) :: CS !< Child structure
  integer,       intent(in)    :: n  !< Array size
  call alloc_only(CS, n)
  call map_only(CS)
end subroutine alloc_map

!> Allocate every allocatable component on the host only
subroutine alloc_only(CS, n)
  type(child_t), intent(inout) :: CS !< Child structure
  integer,       intent(in)    :: n  !< Array size
  allocate(CS%a01(n,n), CS%a02(n,n), CS%a03(n,n), CS%a04(n,n), CS%a05(n,n), CS%a06(n,n))
  allocate(CS%a07(n,n), CS%a08(n,n), CS%a09(n,n), CS%a10(n,n), CS%a11(n,n), CS%a12(n,n))
  allocate(CS%a13(n,n), CS%a14(n,n), CS%a15(n,n), CS%a16(n,n), CS%a17(n,n), CS%a18(n,n))
  allocate(CS%a19(n,n), CS%a20(n,n), CS%a21(n,n), CS%a22(n,n), CS%a23(n,n), CS%a24(n,n))
  allocate(CS%a25(n,n), CS%a26(n,n), CS%a27(n,n), CS%a28(n,n), CS%a29(n,n), CS%a30(n,n))
  allocate(CS%a31(n,n), CS%a32(n,n), CS%a33(n,n), CS%a34(n,n), CS%a35(n,n), CS%a36(n,n))
  allocate(CS%a37(n,n), CS%a38(n,n), CS%a39(n,n), CS%a40(n,n), CS%a41(n,n), CS%a42(n,n))
  allocate(CS%a43(n,n), CS%a44(n,n), CS%a45(n,n), CS%a46(n,n), CS%a47(n,n), CS%a48(n,n))
  allocate(CS%a49(n,n), CS%a50(n,n), CS%a51(n,n), CS%a52(n,n), CS%a53(n,n), CS%a54(n,n))
  allocate(CS%a55(n,n), CS%a56(n,n), CS%a57(n,n), CS%a58(n,n), CS%a59(n,n), CS%a60(n,n))
end subroutine alloc_only

!> Map the data of every allocatable component (attaching it to the device structure)
subroutine map_only(CS)
  type(child_t), intent(inout) :: CS !< Child structure
  !$omp target enter data map(to: CS%a01, CS%a02, CS%a03, CS%a04, CS%a05, CS%a06, CS%a07, CS%a08)
  !$omp target enter data map(to: CS%a09, CS%a10, CS%a11, CS%a12, CS%a13, CS%a14, CS%a15, CS%a16)
  !$omp target enter data map(to: CS%a17, CS%a18, CS%a19, CS%a20, CS%a21, CS%a22, CS%a23, CS%a24)
  !$omp target enter data map(to: CS%a25, CS%a26, CS%a27, CS%a28, CS%a29, CS%a30, CS%a31, CS%a32)
  !$omp target enter data map(to: CS%a33, CS%a34, CS%a35, CS%a36, CS%a37, CS%a38, CS%a39, CS%a40)
  !$omp target enter data map(to: CS%a41, CS%a42, CS%a43, CS%a44, CS%a45, CS%a46, CS%a47, CS%a48)
  !$omp target enter data map(to: CS%a49, CS%a50, CS%a51, CS%a52, CS%a53, CS%a54, CS%a55, CS%a56)
  !$omp target enter data map(to: CS%a57, CS%a58, CS%a59, CS%a60)
end subroutine map_only
#endif

end module init_mod

program reproducer
  use race_mod, only : parent_t, child_t
  use init_mod, only : child_init
  implicit none
#ifdef NSIZE
  integer, parameter :: n = NSIZE
#else
  integer, parameter :: n = 64  ! Each n x n component is 16 KiB, the largest staged transfer
#endif
  integer, parameter :: ntrials = 20
  real :: vals(3)
  integer :: t, nbad, i
  integer :: nbad3(3) = 0  ! The number of wrong reads of each scalar
#ifdef NO_PARENT
  type(child_t), pointer :: C
#else
  type(parent_t), pointer :: P
#endif

  nbad = 0
  do t=1,ntrials
#ifdef NO_PARENT
    allocate(C)
    !$omp target enter data map(alloc: C)
    call child_init(C, n, vals)
#else
    allocate(P)
    !$omp target enter data map(alloc: P)          ! like MOM.F90: map(alloc: CS%dyn_split_RK2_CSp)
    !$omp target enter data map(alloc: P%child)    ! like map(alloc: CS%barotropic_CSp)
#if defined(PARENT_ALLOCS) || defined(PARENT_MANY)
    ! The parent's own components are allocated and mapped before the child is initialized
    allocate(P%p01(n,n), P%p02(n,n), P%p03(n,n), P%p04(n,n), P%p05(n,n))
    allocate(P%p06(n,n), P%p07(n,n), P%p08(n,n), P%p09(n,n), P%p10(n,n))
    !$omp target enter data map(to: P%p01, P%p02, P%p03, P%p04, P%p05)
    !$omp target enter data map(to: P%p06, P%p07, P%p08, P%p09, P%p10)
#endif
#ifdef PARENT_MANY
    allocate(P%p11(n,n), P%p12(n,n), P%p13(n,n), P%p14(n,n), P%p15(n,n))
    allocate(P%p16(n,n), P%p17(n,n), P%p18(n,n), P%p19(n,n), P%p20(n,n))
    allocate(P%p21(n,n), P%p22(n,n), P%p23(n,n), P%p24(n,n), P%p25(n,n))
    allocate(P%p26(n,n), P%p27(n,n), P%p28(n,n), P%p29(n,n), P%p30(n,n))
    allocate(P%p31(n,n), P%p32(n,n), P%p33(n,n), P%p34(n,n), P%p35(n,n))
    allocate(P%p36(n,n), P%p37(n,n), P%p38(n,n), P%p39(n,n), P%p40(n,n))
    allocate(P%p41(n,n), P%p42(n,n), P%p43(n,n), P%p44(n,n), P%p45(n,n))
    allocate(P%p46(n,n), P%p47(n,n), P%p48(n,n), P%p49(n,n), P%p50(n,n))
    allocate(P%p51(n,n), P%p52(n,n), P%p53(n,n), P%p54(n,n), P%p55(n,n))
    allocate(P%p56(n,n), P%p57(n,n), P%p58(n,n), P%p59(n,n), P%p60(n,n))
    !$omp target enter data map(to: P%p11, P%p12, P%p13, P%p14, P%p15)
    !$omp target enter data map(to: P%p16, P%p17, P%p18, P%p19, P%p20)
    !$omp target enter data map(to: P%p21, P%p22, P%p23, P%p24, P%p25)
    !$omp target enter data map(to: P%p26, P%p27, P%p28, P%p29, P%p30)
    !$omp target enter data map(to: P%p31, P%p32, P%p33, P%p34, P%p35)
    !$omp target enter data map(to: P%p36, P%p37, P%p38, P%p39, P%p40)
    !$omp target enter data map(to: P%p41, P%p42, P%p43, P%p44, P%p45)
    !$omp target enter data map(to: P%p46, P%p47, P%p48, P%p49, P%p50)
    !$omp target enter data map(to: P%p51, P%p52, P%p53, P%p54, P%p55)
    !$omp target enter data map(to: P%p56, P%p57, P%p58, P%p59, P%p60)
#endif
#ifdef NPAR
    do i=1,NPAR
      allocate(P%ph(i)%a(n,n))
      !$omp target enter data map(to: P%ph(i)%a)
    enddo
#endif
    call child_init(P%child, n, vals)
#endif
    where (vals /= [0.2, 1.0, 0.9]) nbad3 = nbad3 + 1
    if (any(vals /= [0.2, 1.0, 0.9])) then
      nbad = nbad + 1
      if (nbad <= 3) print '(a,i3,a,3es13.4)', 'trial', t, ': device read bebt, scale, frac =', vals
    endif
    ! Leak the objects on purpose: each trial uses fresh, never-written device memory.
  enddo

  print '(a,i0,a,i0,a,3(1x,i0))', 'wrong device reads: ', nbad, ' of ', ntrials, &
      '; by scalar (bebt, scale, frac):', nbad3
  if (nbad == 0) then
    print '(a)', 'PASS'
  else
    print '(a)', 'FAIL'
    error stop 1
  endif
end program reproducer
