! ifx kernel-argument-size reproducer:
!   Each explicit-shape array referenced in an offloaded loop costs one pointer
!   plus 4 separate 8-byte bounds/stride kernel arguments, even when all arrays
!   share the same bounds.  With 60 such arrays the kernel needs ~2.4 KiB of
!   arguments, above the 2048-byte Intel GPU limit, and the device image fails to
!   build.
!
! Compiler: ifx (IFX) 2026.1.0 20260617 (Aurora, PVC)
!
! JIT (default): compiles, then fails at run time on the GPU:
!   ifx -qopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent reproducer.F90
!   LEVEL_ZERO message: 'error: Total size of kernel arguments exceeds limit! ...'
! AOT: fails at link time, no GPU needed:
!   ifx -qopenmp -fopenmp-targets=spir64_gen -Xopenmp-target-backend "-device pvc" \
!       -fopenmp-target-do-concurrent reproducer.F90
!
! With -DWORKAROUND the arrays are allocatable (1 argument each) and it works.

!> Fills 60 arrays inside a single offloaded loop
subroutine fill(isd, ied, jsd, jed, nz, total)
  implicit none
  integer, intent(in)  :: isd, ied, jsd, jed, nz !< Array bounds
  real,    intent(out) :: total !< A checksum [arbitrary]
#ifdef WORKAROUND
  real, allocatable, dimension(:,:,:) :: &
    a00, a01, a02, a03, a04, a05, a06, a07, &
    a08, a09, a10, a11, a12, a13, a14, a15, &
    a16, a17, a18, a19, a20, a21, a22, a23, &
    a24, a25, a26, a27, a28, a29, a30, a31, &
    a32, a33, a34, a35, a36, a37, a38, a39, &
    a40, a41, a42, a43, a44, a45, a46, a47, &
    a48, a49, a50, a51, a52, a53, a54, a55, &
    a56, a57, a58, a59
#else
  real, dimension(isd:ied,jsd:jed,nz) :: &
    a00, a01, a02, a03, a04, a05, a06, a07, &
    a08, a09, a10, a11, a12, a13, a14, a15, &
    a16, a17, a18, a19, a20, a21, a22, a23, &
    a24, a25, a26, a27, a28, a29, a30, a31, &
    a32, a33, a34, a35, a36, a37, a38, a39, &
    a40, a41, a42, a43, a44, a45, a46, a47, &
    a48, a49, a50, a51, a52, a53, a54, a55, &
    a56, a57, a58, a59
#endif
  integer :: i, j, k

#ifdef WORKAROUND
  allocate(a00(isd:ied,jsd:jed,nz))
  allocate(a01(isd:ied,jsd:jed,nz))
  allocate(a02(isd:ied,jsd:jed,nz))
  allocate(a03(isd:ied,jsd:jed,nz))
  allocate(a04(isd:ied,jsd:jed,nz))
  allocate(a05(isd:ied,jsd:jed,nz))
  allocate(a06(isd:ied,jsd:jed,nz))
  allocate(a07(isd:ied,jsd:jed,nz))
  allocate(a08(isd:ied,jsd:jed,nz))
  allocate(a09(isd:ied,jsd:jed,nz))
  allocate(a10(isd:ied,jsd:jed,nz))
  allocate(a11(isd:ied,jsd:jed,nz))
  allocate(a12(isd:ied,jsd:jed,nz))
  allocate(a13(isd:ied,jsd:jed,nz))
  allocate(a14(isd:ied,jsd:jed,nz))
  allocate(a15(isd:ied,jsd:jed,nz))
  allocate(a16(isd:ied,jsd:jed,nz))
  allocate(a17(isd:ied,jsd:jed,nz))
  allocate(a18(isd:ied,jsd:jed,nz))
  allocate(a19(isd:ied,jsd:jed,nz))
  allocate(a20(isd:ied,jsd:jed,nz))
  allocate(a21(isd:ied,jsd:jed,nz))
  allocate(a22(isd:ied,jsd:jed,nz))
  allocate(a23(isd:ied,jsd:jed,nz))
  allocate(a24(isd:ied,jsd:jed,nz))
  allocate(a25(isd:ied,jsd:jed,nz))
  allocate(a26(isd:ied,jsd:jed,nz))
  allocate(a27(isd:ied,jsd:jed,nz))
  allocate(a28(isd:ied,jsd:jed,nz))
  allocate(a29(isd:ied,jsd:jed,nz))
  allocate(a30(isd:ied,jsd:jed,nz))
  allocate(a31(isd:ied,jsd:jed,nz))
  allocate(a32(isd:ied,jsd:jed,nz))
  allocate(a33(isd:ied,jsd:jed,nz))
  allocate(a34(isd:ied,jsd:jed,nz))
  allocate(a35(isd:ied,jsd:jed,nz))
  allocate(a36(isd:ied,jsd:jed,nz))
  allocate(a37(isd:ied,jsd:jed,nz))
  allocate(a38(isd:ied,jsd:jed,nz))
  allocate(a39(isd:ied,jsd:jed,nz))
  allocate(a40(isd:ied,jsd:jed,nz))
  allocate(a41(isd:ied,jsd:jed,nz))
  allocate(a42(isd:ied,jsd:jed,nz))
  allocate(a43(isd:ied,jsd:jed,nz))
  allocate(a44(isd:ied,jsd:jed,nz))
  allocate(a45(isd:ied,jsd:jed,nz))
  allocate(a46(isd:ied,jsd:jed,nz))
  allocate(a47(isd:ied,jsd:jed,nz))
  allocate(a48(isd:ied,jsd:jed,nz))
  allocate(a49(isd:ied,jsd:jed,nz))
  allocate(a50(isd:ied,jsd:jed,nz))
  allocate(a51(isd:ied,jsd:jed,nz))
  allocate(a52(isd:ied,jsd:jed,nz))
  allocate(a53(isd:ied,jsd:jed,nz))
  allocate(a54(isd:ied,jsd:jed,nz))
  allocate(a55(isd:ied,jsd:jed,nz))
  allocate(a56(isd:ied,jsd:jed,nz))
  allocate(a57(isd:ied,jsd:jed,nz))
  allocate(a58(isd:ied,jsd:jed,nz))
  allocate(a59(isd:ied,jsd:jed,nz))
#endif
  !$omp target enter data map(alloc: &
  !$omp   a00, a01, a02, a03, a04, a05, a06, a07, &
  !$omp   a08, a09, a10, a11, a12, a13, a14, a15, &
  !$omp   a16, a17, a18, a19, a20, a21, a22, a23, &
  !$omp   a24, a25, a26, a27, a28, a29, a30, a31, &
  !$omp   a32, a33, a34, a35, a36, a37, a38, a39, &
  !$omp   a40, a41, a42, a43, a44, a45, a46, a47, &
  !$omp   a48, a49, a50, a51, a52, a53, a54, a55, &
  !$omp   a56, a57, a58, a59)

  do concurrent (k=1:nz, j=jsd:jed, i=isd:ied)
    a00(i,j,k) = real(1)
    a01(i,j,k) = real(2)
    a02(i,j,k) = real(3)
    a03(i,j,k) = real(4)
    a04(i,j,k) = real(5)
    a05(i,j,k) = real(6)
    a06(i,j,k) = real(7)
    a07(i,j,k) = real(8)
    a08(i,j,k) = real(9)
    a09(i,j,k) = real(10)
    a10(i,j,k) = real(11)
    a11(i,j,k) = real(12)
    a12(i,j,k) = real(13)
    a13(i,j,k) = real(14)
    a14(i,j,k) = real(15)
    a15(i,j,k) = real(16)
    a16(i,j,k) = real(17)
    a17(i,j,k) = real(18)
    a18(i,j,k) = real(19)
    a19(i,j,k) = real(20)
    a20(i,j,k) = real(21)
    a21(i,j,k) = real(22)
    a22(i,j,k) = real(23)
    a23(i,j,k) = real(24)
    a24(i,j,k) = real(25)
    a25(i,j,k) = real(26)
    a26(i,j,k) = real(27)
    a27(i,j,k) = real(28)
    a28(i,j,k) = real(29)
    a29(i,j,k) = real(30)
    a30(i,j,k) = real(31)
    a31(i,j,k) = real(32)
    a32(i,j,k) = real(33)
    a33(i,j,k) = real(34)
    a34(i,j,k) = real(35)
    a35(i,j,k) = real(36)
    a36(i,j,k) = real(37)
    a37(i,j,k) = real(38)
    a38(i,j,k) = real(39)
    a39(i,j,k) = real(40)
    a40(i,j,k) = real(41)
    a41(i,j,k) = real(42)
    a42(i,j,k) = real(43)
    a43(i,j,k) = real(44)
    a44(i,j,k) = real(45)
    a45(i,j,k) = real(46)
    a46(i,j,k) = real(47)
    a47(i,j,k) = real(48)
    a48(i,j,k) = real(49)
    a49(i,j,k) = real(50)
    a50(i,j,k) = real(51)
    a51(i,j,k) = real(52)
    a52(i,j,k) = real(53)
    a53(i,j,k) = real(54)
    a54(i,j,k) = real(55)
    a55(i,j,k) = real(56)
    a56(i,j,k) = real(57)
    a57(i,j,k) = real(58)
    a58(i,j,k) = real(59)
    a59(i,j,k) = real(60)
  enddo

  !$omp target exit data map(from: &
  !$omp   a00, a01, a02, a03, a04, a05, a06, a07, &
  !$omp   a08, a09, a10, a11, a12, a13, a14, a15, &
  !$omp   a16, a17, a18, a19, a20, a21, a22, a23, &
  !$omp   a24, a25, a26, a27, a28, a29, a30, a31, &
  !$omp   a32, a33, a34, a35, a36, a37, a38, a39, &
  !$omp   a40, a41, a42, a43, a44, a45, a46, a47, &
  !$omp   a48, a49, a50, a51, a52, a53, a54, a55, &
  !$omp   a56, a57, a58, a59)
  total = a00(isd,jsd,1) + a01(isd,jsd,1) + a02(isd,jsd,1) + a03(isd,jsd,1)
end subroutine fill

program reproducer
  implicit none
  real :: total
  call fill(0, 9, 0, 9, 3, total)
  if (total == 10.0) then
    print '(a)', 'PASS'
  else
    print '(a,f8.2)', 'FAIL: total = ', total
    error stop 1
  endif
end program reproducer
