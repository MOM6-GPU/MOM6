module m
  implicit none
  type :: t0
    type(t1), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t1
    type(t2), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t2
    type(t3), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t3
    type(t4), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t4
    type(t5), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t5
    type(t6), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t6
    type(t7), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t7
    type(t8), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t8
    type(t9), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t9
    type(t10), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t10
    type(t11), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t11
    type(t12), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t12
    type(t13), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t13
    type(t14), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t14
    type(t15), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t15
    type(t16), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t16
    type(t17), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t17
    type(t18), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t18
    type(t19), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t19
    type(t20), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t20
    type(t21), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t21
    type(t22), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t22
    type(t23), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t23
    type(t24), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t24
    type(t25), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t25
    type(t26), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t26
    type(t27), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t27
    type(t28), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t28
    type(t29), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t29
    type(t30), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t30
    type(t31), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t31
    type(t32), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t32
    type(t33), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t33
    type(t34), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t34
    type(t35), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t35
    type(t36), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t36
    type(t37), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t37
    type(t38), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t38
    type(t39), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
  type :: t39
    type(t0), pointer :: p => null()
    real, allocatable :: v(:,:)
  end type
contains
  subroutine s0(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s0
  subroutine s1(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s1
  subroutine s2(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s2
  subroutine s3(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s3
  subroutine s4(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s4
  subroutine s5(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s5
  subroutine s6(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s6
  subroutine s7(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s7
  subroutine s8(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s8
  subroutine s9(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s9
  subroutine s10(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s10
  subroutine s11(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s11
  subroutine s12(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s12
  subroutine s13(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s13
  subroutine s14(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s14
  subroutine s15(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s15
  subroutine s16(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s16
  subroutine s17(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s17
  subroutine s18(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s18
  subroutine s19(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s19
  subroutine s20(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s20
  subroutine s21(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s21
  subroutine s22(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s22
  subroutine s23(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s23
  subroutine s24(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s24
  subroutine s25(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s25
  subroutine s26(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s26
  subroutine s27(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s27
  subroutine s28(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s28
  subroutine s29(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s29
  subroutine s30(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s30
  subroutine s31(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s31
  subroutine s32(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s32
  subroutine s33(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s33
  subroutine s34(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s34
  subroutine s35(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s35
  subroutine s36(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s36
  subroutine s37(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s37
  subroutine s38(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s38
  subroutine s39(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s39
  subroutine s40(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s40
  subroutine s41(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s41
  subroutine s42(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s42
  subroutine s43(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s43
  subroutine s44(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s44
  subroutine s45(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s45
  subroutine s46(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s46
  subroutine s47(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s47
  subroutine s48(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s48
  subroutine s49(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s49
  subroutine s50(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s50
  subroutine s51(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s51
  subroutine s52(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s52
  subroutine s53(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s53
  subroutine s54(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s54
  subroutine s55(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s55
  subroutine s56(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s56
  subroutine s57(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s57
  subroutine s58(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s58
  subroutine s59(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s59
  subroutine s60(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s60
  subroutine s61(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s61
  subroutine s62(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s62
  subroutine s63(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    integer, intent(in) :: ni, nj, nk
    real, intent(inout) :: a(ni,nj,nk)
    integer :: i, j, k
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s63
end module m
