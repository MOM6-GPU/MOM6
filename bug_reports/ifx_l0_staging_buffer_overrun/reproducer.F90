! Intel OpenMP offload runtime (Level Zero) bug: a `target update` that expands into many
! small host-to-device transfers, behind one large transfer, leaves wrong data on the device.
!
!   ifx -O3 -qopenmp -fopenmp-targets=spir64 reproducer.F90 && ./a.out
!
! Expected: the kernel reads 0.2, 1.0, 0.9 in every trial.
! Observed (default settings, PVC): wrong values (e.g. NaN) in 19 of 20 trials.
! Correct with LIBOMPTARGET_LEVEL_ZERO_COMMAND_MODE=sync or
! LIBOMPTARGET_LEVEL_ZERO_STAGING_BUFFER_SIZE=0.
!
! `update to(C)` becomes one large transfer of C (about 290 KB, not staged) plus one entry per
! allocatable component of C.  After each entry the runtime rewrites every pointer attached in
! the enclosing mapped parent (60 here) with an 8-byte transfer, each going through a staging
! buffer: thousands of small transfers queue up behind the large one.
!
!   -DWORKAROUND  update C through a byte view of its storage (a single map entry): correct
!   -DNO_PAD      C is small (about 4.5 KB), so its own transfer is staged too: correct
module repro_mod
  implicit none
  private
  public :: parent_t, child_t

  !> A structure with allocatable components (allocated on the host, not mapped)
  type :: child_t
    real, allocatable :: c01(:), c02(:), c03(:), c04(:), c05(:), c06(:), c07(:), c08(:), c09(:), c10(:), &
      c11(:), c12(:), c13(:), c14(:), c15(:), c16(:), c17(:), c18(:), c19(:), c20(:), &
      c21(:), c22(:), c23(:), c24(:), c25(:), c26(:), c27(:), c28(:), c29(:), c30(:), &
      c31(:), c32(:), c33(:), c34(:), c35(:), c36(:), c37(:), c38(:), c39(:), c40(:), &
      c41(:), c42(:), c43(:), c44(:), c45(:), c46(:), c47(:), c48(:), c49(:), c50(:), &
      c51(:), c52(:), c53(:), c54(:), c55(:), c56(:), c57(:), c58(:), c59(:), c60(:)
#ifndef NO_PAD
    real :: pad(36000) = 0.0   !< Makes C large (~290 KB), so its own transfer is not staged
#endif
    real :: bebt = -1.0, scale = -1.0, frac = -1.0  !< Scalars read on the device
  end type child_t

  !> The enclosing structure, with mapped allocatable components
  type :: parent_t
    real, allocatable :: p01(:), p02(:), p03(:), p04(:), p05(:), p06(:), p07(:), p08(:), p09(:), p10(:), &
      p11(:), p12(:), p13(:), p14(:), p15(:), p16(:), p17(:), p18(:), p19(:), p20(:), &
      p21(:), p22(:), p23(:), p24(:), p25(:), p26(:), p27(:), p28(:), p29(:), p30(:), &
      p31(:), p32(:), p33(:), p34(:), p35(:), p36(:), p37(:), p38(:), p39(:), p40(:), &
      p41(:), p42(:), p43(:), p44(:), p45(:), p46(:), p47(:), p48(:), p49(:), p50(:), &
      p51(:), p52(:), p53(:), p54(:), p55(:), p56(:), p57(:), p58(:), p59(:), p60(:)
    type(child_t) :: child
  end type parent_t
end module repro_mod

module init_mod
  use, intrinsic :: iso_c_binding, only : c_loc, c_f_pointer, c_int8_t
  use repro_mod, only : child_t
  implicit none
  private
  public :: init_child
contains

!> Allocate C's components on the host, set its scalars, update the device copy, read it back
subroutine init_child(C, vals)
  type(child_t), target, intent(inout) :: C       !< Child, part of a mapped parent
  real,                  intent(out)   :: vals(3) !< Scalars as read on the device
#ifdef WORKAROUND
  integer(c_int8_t), pointer :: C_bytes(:)
#endif
  allocate(C%c01(8), C%c02(8), C%c03(8), C%c04(8), C%c05(8), C%c06(8))
  allocate(C%c07(8), C%c08(8), C%c09(8), C%c10(8), C%c11(8), C%c12(8))
  allocate(C%c13(8), C%c14(8), C%c15(8), C%c16(8), C%c17(8), C%c18(8))
  allocate(C%c19(8), C%c20(8), C%c21(8), C%c22(8), C%c23(8), C%c24(8))
  allocate(C%c25(8), C%c26(8), C%c27(8), C%c28(8), C%c29(8), C%c30(8))
  allocate(C%c31(8), C%c32(8), C%c33(8), C%c34(8), C%c35(8), C%c36(8))
  allocate(C%c37(8), C%c38(8), C%c39(8), C%c40(8), C%c41(8), C%c42(8))
  allocate(C%c43(8), C%c44(8), C%c45(8), C%c46(8), C%c47(8), C%c48(8))
  allocate(C%c49(8), C%c50(8), C%c51(8), C%c52(8), C%c53(8), C%c54(8))
  allocate(C%c55(8), C%c56(8), C%c57(8), C%c58(8), C%c59(8), C%c60(8))
  C%bebt = 0.2 ; C%scale = 1.0 ; C%frac = 0.9
#ifdef WORKAROUND
  call c_f_pointer(c_loc(C), C_bytes, [storage_size(C)/8])
  !$omp target update to(C_bytes)
#else
  !$omp target update to(C)
#endif
  vals(:) = -7.0
  !$omp target map(from: vals)
  vals(1) = C%bebt ; vals(2) = C%scale ; vals(3) = C%frac
  !$omp end target
end subroutine init_child
end module init_mod

program reproducer
  use repro_mod, only : parent_t
  use init_mod, only : init_child
  implicit none
  integer, parameter :: ntrials = 20
  type(parent_t), pointer :: P
  real :: vals(3)
  integer :: t, nbad

  nbad = 0
  do t=1,ntrials
    allocate(P)
    !$omp target enter data map(alloc: P)
    allocate(P%p01(8), P%p02(8), P%p03(8), P%p04(8), P%p05(8), P%p06(8))
    allocate(P%p07(8), P%p08(8), P%p09(8), P%p10(8), P%p11(8), P%p12(8))
    allocate(P%p13(8), P%p14(8), P%p15(8), P%p16(8), P%p17(8), P%p18(8))
    allocate(P%p19(8), P%p20(8), P%p21(8), P%p22(8), P%p23(8), P%p24(8))
    allocate(P%p25(8), P%p26(8), P%p27(8), P%p28(8), P%p29(8), P%p30(8))
    allocate(P%p31(8), P%p32(8), P%p33(8), P%p34(8), P%p35(8), P%p36(8))
    allocate(P%p37(8), P%p38(8), P%p39(8), P%p40(8), P%p41(8), P%p42(8))
    allocate(P%p43(8), P%p44(8), P%p45(8), P%p46(8), P%p47(8), P%p48(8))
    allocate(P%p49(8), P%p50(8), P%p51(8), P%p52(8), P%p53(8), P%p54(8))
    allocate(P%p55(8), P%p56(8), P%p57(8), P%p58(8), P%p59(8), P%p60(8))
    !$omp target enter data map(to: P%p01, P%p02, P%p03, P%p04, P%p05, P%p06)
    !$omp target enter data map(to: P%p07, P%p08, P%p09, P%p10, P%p11, P%p12)
    !$omp target enter data map(to: P%p13, P%p14, P%p15, P%p16, P%p17, P%p18)
    !$omp target enter data map(to: P%p19, P%p20, P%p21, P%p22, P%p23, P%p24)
    !$omp target enter data map(to: P%p25, P%p26, P%p27, P%p28, P%p29, P%p30)
    !$omp target enter data map(to: P%p31, P%p32, P%p33, P%p34, P%p35, P%p36)
    !$omp target enter data map(to: P%p37, P%p38, P%p39, P%p40, P%p41, P%p42)
    !$omp target enter data map(to: P%p43, P%p44, P%p45, P%p46, P%p47, P%p48)
    !$omp target enter data map(to: P%p49, P%p50, P%p51, P%p52, P%p53, P%p54)
    !$omp target enter data map(to: P%p55, P%p56, P%p57, P%p58, P%p59, P%p60)
    call init_child(P%child, vals)
    if (any(vals /= [0.2, 1.0, 0.9])) then
      nbad = nbad + 1
      if (nbad <= 3) print '(a,i3,a,3es13.4)', 'trial', t, ': device read', vals
    endif
  enddo   ! objects are leaked on purpose: every trial uses fresh device memory
  print '(a,i0,a,i0)', 'wrong device reads: ', nbad, ' of ', ntrials
  if (nbad > 0) error stop 1
end program reproducer
