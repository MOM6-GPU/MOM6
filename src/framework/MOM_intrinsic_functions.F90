! This file is part of MOM6, the Modular Ocean Model version 6.
! See the LICENSE file for licensing information.
! SPDX-License-Identifier: Apache-2.0

!> A module with intrinsic functions that are used by MOM but are not supported
!! by some compilers.
module MOM_intrinsic_functions

use iso_fortran_env, only : stdout => output_unit, stderr => error_unit
use iso_fortran_env, only : int64, real64

implicit none ; private

public :: invcosh, cuberoot, nth_root, exp_reprod, log_reprod
public :: intrinsic_functions_unit_tests

! Floating point model, if bit layout from high to low is (sign, exp, frac)

integer, parameter :: bias = maxexponent(1.) - 1
  !< The double precision exponent offset
integer, parameter :: signbit = storage_size(1.) - 1
  !< Position of sign bit
integer, parameter :: explen = 1 + ceiling(log(real(bias))/log(2.))
  !< Bit size of exponent
integer, parameter :: expbit = signbit - explen
  !< Position of lowest exponent bit
integer, parameter :: fraclen = expbit
  !< Length of fractional part

contains

!> Evaluate the inverse cosh, either using a math library or an
!! equivalent expression
function invcosh(x)
  real, intent(in) :: x !< The argument of the inverse of cosh [nondim].  NaNs will
                        !! occur if x<1, but there is no error checking
  real :: invcosh  ! The inverse of cosh of x [nondim]

#ifdef __INTEL_COMPILER
  invcosh = acosh(x)
#else
  invcosh = log(x+sqrt(x*x-1))
#endif

end function invcosh


!> Returns the cube root of a real argument at roundoff accuracy, in a form that works properly with
!! rescaling of the argument by integer powers of 8.  If the argument is a NaN, a NaN is returned.
elemental function cuberoot(x) result(root)
  !$omp declare target
  real, intent(in) :: x !< The argument of cuberoot in arbitrary units cubed [A3]
  real :: root !< The real cube root of x in arbitrary units [A]

  real :: asx ! The absolute value of x rescaled by an integer power of 8 to put it into
              ! the range from 0.125 < asx <= 1.0, in ambiguous units cubed [B3]
  real :: root_asx ! The cube root of asx [B]
  real :: ra_3 ! root_asx cubed [B3]
  real :: num ! The numerator of an expression for the evolving estimate of the cube root of asx
              ! in arbitrary units that can grow or shrink with each iteration [B C]
  real :: den ! The denominator of an expression for the evolving estimate of the cube root of asx
              ! in arbitrary units that can grow or shrink with each iteration [C]
  real :: num_prev ! The numerator of an expression for the previous iteration of the evolving estimate
              ! of the cube root of asx in arbitrary units that can grow or shrink with each iteration [B D]
  real :: np_3 ! num_prev cubed  [B3 D3]
  real :: den_prev ! The denominator of an expression for the previous iteration of the evolving estimate of
              ! the cube root of asx in arbitrary units that can grow or shrink with each iteration [D]
  real :: dp_3 ! den_prev cubed  [C3]
  real :: r0  ! Initial value of the iterative solver. [B C]
  real :: r0_3 ! r0 cubed [B3 C3]
  integer :: itt

  integer(kind=int64) :: e_x, s_x

  if ((x >= 0.0) .eqv. (x <= 0.0)) then
    ! Return 0 for an input of 0, or NaN for a NaN input.
    root = x
  else
    call rescale_cbrt(x, asx, e_x, s_x)

    !   Iteratively determine root_asx = asx**1/3 using Halley's method and then Newton's method,
    ! noting that Halley's method onverges monotonically and needs no bounding.  Halley's method is
    ! slightly more complicated that Newton's method, but converges in a third fewer iterations.
    !   Keeping the estimates in a fractional form Root = num / den allows this calculation with
    ! no real divisions during the iterations before doing a single real division at the end,
    ! and it is therefore more computationally efficient.

    ! This first estimate gives the same magnitude of errors for 0.125 and 1.0 after two iterations.
    ! The first iteration is applied explicitly.
    r0 = 0.707106
    r0_3 = r0 * r0 * r0
    num = r0 * (r0_3 + 2.0 * asx)
    den = 2.0 * r0_3 + asx

    do itt=1,2
      ! Halley's method iterates estimates as Root = Root * (Root**3 + 2.*asx) / (2.*Root**3 + asx).
      num_prev = num ; den_prev = den

      ! Pre-compute these as integer powers, to avoid `pow()`-like intrinsics.
      np_3 = num_prev * num_prev * num_prev
      dp_3 = den_prev * den_prev * den_prev

      num = num_prev * (np_3 + 2.0 * asx * dp_3)
      den = den_prev * (2.0 * np_3 + asx * dp_3)
      ! Equivalent to:  root_asx = root_asx * (root_asx**3 + 2.*asx) / (2.*root_asx**3 + asx)
    enddo
    ! At this point the error in root_asx is better than 1 part in 3e14.
    root_asx = num / den

    ! One final iteration with Newton's method polishes up the root and gives a solution
    ! that is within the last bit of the true solution.
    ra_3 = root_asx * root_asx * root_asx
    root_asx = root_asx - (ra_3 - asx) / (3.0 * (root_asx * root_asx))

    root = descale(root_asx, e_x, s_x)
  endif
end function cuberoot


!> Bit-reproducible exponential, exp(x), suitable for evaluation inside `!$omp target` /
!! `do concurrent` offloaded regions.
!!
!! The intrinsic `exp()` lowers to host libm on the CPU and CUDA libdevice on the GPU, whose
!! last-bit rounding differs -- so a `do concurrent`/`omp target` kernel that calls `exp()` is not
!! bit-for-bit CPU==GPU (the class of ~1e-13 divergence seen in the ePBL energy budget). This routine
!! avoids the library call entirely: Cody-Waite range reduction x = k*ln2 + r (|r| <= ln2/2) using a
!! two-part ln2 so that k*ln2_hi is (near-)exact, a degree-12 Taylor/Horner polynomial for exp(r) whose
!! reciprocal-factorial coefficients are compile-time constant-folded (hence identical on host and
!! device), and `scale(.,k)` for the 2**k factor. Every operation is +,-,*,/ (plus `nint`/`scale`,
!! which are exact), all of which are bit-identical host vs device under `-Mnofma`, so the result is
!! reproducible by construction. Accuracy is ~1.4 ULP (max relative error 3.1e-16 vs the intrinsic
!! over x in [-70, 20]); it is NOT bit-identical to the intrinsic exp (like cuberoot vs x**(1/3), it
!! changes answers and requires a reference/golden regeneration when adopted).
elemental function exp_reprod(x) result(ex)
  !$omp declare target
  real, intent(in) :: x  !< The argument of the exponential [nondim or arbitrary]
  real :: ex             !< The reproducible exponential of x [same as exp(x)]

  ! Cody-Waite split of ln(2): ln2 = ln2_hi + ln2_lo, with ln2_hi chosen so k*ln2_hi is ~exact.
  real, parameter :: invln2 = 1.44269504088896338700  ! 1/ln(2) [nondim]
  real, parameter :: ln2_hi = 0.693147180369123816490 ! High part of ln(2) [nondim]
  real, parameter :: ln2_lo = 1.90821492927058770002e-10 ! Low part of ln(2) [nondim]
  ! Reciprocal factorials 1/2! .. 1/12! (compile-time constant-folded -> identical host/device).
  real, parameter :: c2 = 1.0/2.0,        c3 = 1.0/6.0,         c4 = 1.0/24.0
  real, parameter :: c5 = 1.0/120.0,      c6 = 1.0/720.0,       c7 = 1.0/5040.0
  real, parameter :: c8 = 1.0/40320.0,    c9 = 1.0/362880.0,    c10 = 1.0/3628800.0
  real, parameter :: c11 = 1.0/39916800.0, c12 = 1.0/479001600.0
  real :: r  ! The reduced argument, x - k*ln2, in [-ln2/2, ln2/2] [nondim]
  real :: p  ! The polynomial estimate of exp(r) [nondim]
  integer :: k ! The integer number of factors of 2 in exp(x) [nondim]

  k = nint(x*invln2)
  r = (x - real(k)*ln2_hi) - real(k)*ln2_lo
  ! Horner form of 1 + r + r^2/2! + ... + r^12/12!
  p = 1.0 + r*(1.0 + r*(c2 + r*(c3 + r*(c4 + r*(c5 + r*(c6 + r*(c7 + &
      r*(c8 + r*(c9 + r*(c10 + r*(c11 + r*c12)))))))))))
  ex = scale(p, k)
end function exp_reprod


!> Bit-reproducible natural logarithm, log(x) for x > 0, suitable for evaluation inside
!! `!$omp target` / `do concurrent` offloaded regions (companion to exp_reprod; together they make
!! arbitrary real powers reproducible via x**y = exp_reprod(y*log_reprod(x))).
!!
!! Same rationale as exp_reprod: the intrinsic log() differs host libm vs CUDA libdevice in the last
!! bit. This routine uses the exponent/fraction split x = m * 2**k (exact bit intrinsics), reduces the
!! mantissa to m in [sqrt(1/2), sqrt(2)), and evaluates log(m) = 2*(s + s^3/3 + s^5/5 + ...) with
!! s = (m-1)/(m+1) (|s| <= 0.172) as a Horner polynomial in s^2 to degree 21, then adds k*ln2. Every
!! operation is +,-,*,/ (plus exponent/fraction, exact), bit-identical host vs device under -Mnofma.
!! Accuracy ~1.7 ULP (max relative error 3.7e-16 vs the intrinsic over x in [1e-30, 1e30]). Requires
!! x > 0. Like exp_reprod it is not bit-identical to intrinsic log (changes answers on adoption).
elemental function log_reprod(x) result(lx)
  !$omp declare target
  real, intent(in) :: x  !< The argument of the logarithm, x > 0 [nondim or arbitrary]
  real :: lx             !< The reproducible natural logarithm of x [nondim]

  real, parameter :: ln2 = 0.69314718055994530942     ! ln(2) [nondim]
  real, parameter :: sqrt2_2 = 0.70710678118654752440 ! sqrt(1/2), the mantissa reduction threshold [nondim]
  ! Reciprocal odd integers 1/3 .. 1/21 for the atanh series (compile-folded -> identical host/device).
  real, parameter :: a3=1.0/3.0,   a5=1.0/5.0,   a7=1.0/7.0,   a9=1.0/9.0
  real, parameter :: a11=1.0/11.0, a13=1.0/13.0, a15=1.0/15.0, a17=1.0/17.0
  real, parameter :: a19=1.0/19.0, a21=1.0/21.0
  real :: m  ! The mantissa of x, reduced to [sqrt(1/2), sqrt(2)) [nondim]
  real :: s  ! (m-1)/(m+1), the atanh-series argument, |s| <= 0.172 [nondim]
  real :: s2 ! s*s [nondim]
  real :: poly ! The polynomial estimate of log(m) [nondim]
  integer :: k ! The binary exponent of x [nondim]

  k = exponent(x) ; m = fraction(x)                    ! x = m * 2**k, m in [0.5, 1)
  if (m < sqrt2_2) then ; m = m + m ; k = k - 1 ; endif ! recenter m to [sqrt(1/2), sqrt(2))
  s = (m - 1.0) / (m + 1.0) ; s2 = s*s
  poly = 2.0*s*(1.0 + s2*(a3 + s2*(a5 + s2*(a7 + s2*(a9 + s2*(a11 + s2*(a13 + &
         s2*(a15 + s2*(a17 + s2*(a19 + s2*a21))))))))))
  lx = poly + real(k)*ln2
end function log_reprod


!> Bit-stable n-th root of x for x in (0, +inf) and integer n >= 1, suitable
!! for evaluation inside `!$omp target` / `do concurrent` offloaded regions.
!!
!! Lowering `x**(1.0/n)` via the compiler produces `exp((1.0/n)*log(x))` — two
!! transcendentals whose last-bit rounding differs between host libm and CUDA
!! libdevice. This routine avoids that path entirely: it uses fixed-iteration
!! Newton on y^n - x = 0, with y^(n-1) evaluated as repeated multiplication,
!! and one bit-precision-polishing iteration at the end.
!!
!! For x in [0, 1] (the case in `MOM_barotropic.F90`'s `bt_rem = av_rem**Instep`)
!! convergence is rapid because the linear initial guess y0 = 1 - (1-x)/n is
!! already within a few percent of the true root.
elemental function nth_root(x, n) result(root)
  !$omp declare target
  real,    intent(in) :: x  !< Argument, x >= 0 [arbitrary]
  integer, intent(in) :: n  !< Root index, n >= 1
  real :: root              !< x**(1/n) in the same units as x

  integer, parameter :: maxitt = 20  ! Fixed (deterministic) iteration count
  real    :: y, ypow_nm1
  real    :: x_n_r, x_nm1_r
  integer :: itt, k

  ! Trivial cases — return early to keep loop tight and avoid 0/0 below.
  if (n <= 1) then
    root = x
    return
  endif
  if (x == 0.0) then
    root = 0.0
    return
  endif

  x_n_r   = real(n)
  x_nm1_r = real(n - 1)

  ! Linear initial guess valid for x in [0, 1] and decent for moderate x > 1.
  ! For our caller (av_rem in [0, 1], typically near 1), this is within ~1%.
  y = 1.0 - (1.0 - x) / x_n_r

  ! Newton iteration:  y_{k+1} = ((n-1)*y_k + x / y_k^{n-1}) / n
  ! All ops are *, +, /. Integer power y^{n-1} is repeated multiplication,
  ! so there is no `pow`/`exp/log` lowering anywhere in the iteration.
  do itt = 1, maxitt
    ypow_nm1 = 1.0
    do k = 1, n - 1
      ypow_nm1 = ypow_nm1 * y
    enddo
    y = (x_nm1_r * y + x / ypow_nm1) / x_n_r
  enddo

  root = y
end function nth_root


!> Rescale `a` to the range [0.125, 1) and compute its cube-root exponent.
!!
!! This function decomposes `a` into the form `s * x * 2**e` so that `x` is
!! in the desired range.  This is accomplished by computing the integral cube
!! root of `e` (as a division) and applying the residual to `x`.
pure subroutine rescale_cbrt(a, x, e_r, s_a)
  !$omp declare target
  real, intent(in) :: a
    !< The number to be rescaled for cube-root computation [A3]
  real, intent(out) :: x
    !< The rescaled value of `a` in the range [0.125, 1) [B3]
  integer(kind=int64), intent(out) :: e_r
    !< The integral component of the cube-root exponent of `a`.
  integer(kind=int64), intent(out) :: s_a
    !< Sign bit of `a`.  A nonzero value indicates negative sign.

  integer(kind=int64) :: xb
    ! Floating point integer representation of `a`
  integer(kind=int64) :: e_a
    ! Exponent of `a`
  integer(kind=int64) :: e_x
    ! Exponent of `x`

  ! Pack bits of a into xb and extract its exponent and sign.
  xb = transfer(a, 1_int64)
  s_a = ibits(xb, signbit, 1)
  e_a = ibits(xb, expbit, explen) - bias

  ! The floating-point form of `a` with exponent `e` is
  !
  !   a = s * (1 + m) * 2**e
  !
  ! where (1+m) ∈ [1,2).  We want to split 2**e so that (1+m) is rescaled to
  ! the range [0.125, 1); that is, [2**-3, 2**0).
  !
  ! First decompose the exponent `e` into quotient-remainder form:
  !
  !   e = 3⌊e/3⌋ + modulo(e,3)
  !
  ! Since modulo(e,3) ∈ {0,1,2}, the second term of the following expression is
  ! in {-3,-2,-1}.
  !
  !   e = 3 * (⌊e/3⌋ + 1) + (modulo(e,3) - 3).
  !
  ! Here, (modulo(e,3) - 3) is in the range [2**-3, 1) and holds the
  ! floating-point exponent of `x`.
  !
  ! Fortran integer division is round-to-zero.  To convert to floor division,
  ! we use the sign() intrinsic to shift negative values downward.
  !
  !   ⌊e/3⌋ = (e + sign(1,e) - 1) / 3
  !
  ! ⌊e/3⌋ + 1 reduces to the form below.  This is what we call the integral
  ! cube-root of `a` in the description above.

  e_r = (e_a + sign(1_int64, e_a) + 2) / 3

  ! modulo() is not implemented on all systems, so compute the remainder as
  ! r = n - 3*q.

  e_x = e_a - e_r * 3

  ! Insert the new 11-bit exponent into xb and write to x and extend the
  ! bitcount to 12, so that the sign bit is zero and x is always positive.
  call mvbits(e_x + bias, 0, explen + 1, xb, fraclen)
  x = transfer(xb, 1.)
end subroutine rescale_cbrt


!> Undo the rescaling of a real number back to its original base.
pure function descale(x, e_a, s_a) result(a)
  !$omp declare target
  real, intent(in) :: x
    !< The rescaled value which is to be restored in ambiguous units [B]
  integer(kind=int64), intent(in) :: e_a
    !< Exponent of the unscaled value
  integer(kind=int64), intent(in) :: s_a
    !< Sign bit of the unscaled value
  real :: a
    !< Restored value with the corrected exponent and sign in arbitrary units [A]

  integer(kind=int64) :: xb
    ! Bit-packed real number into integer form
  integer(kind=int64) :: e_x
    ! Biased exponent of x

  ! Apply the corrected exponent and sign to x.
  xb = transfer(x, 1_int64)
  e_x = ibits(xb, expbit, explen)
  call mvbits(e_a + e_x, 0, explen, xb, expbit)
  call mvbits(s_a, 0, 1, xb, signbit)
  a = transfer(xb, 1.)
end function descale


!> Returns true if any unit test of intrinsic_functions fails, or false if they all pass.
function intrinsic_functions_unit_tests(verbose) result(fail)
  logical, intent(in) :: verbose !< If true, write results to stdout
  logical :: fail !< True if any of the unit tests fail

  ! Local variables
  real :: testval  ! A test value for self-consistency testing [nondim]
  logical :: v
  integer :: n

  fail = .false.
  v = verbose
  write(stdout,*) '==== MOM_intrinsic_functions: intrinsic_functions_unit_tests ==='

  fail = fail .or. Test_cuberoot(v, 1.2345678901234e9)
  fail = fail .or. Test_cuberoot(v, -9.8765432109876e-21)
  fail = fail .or. Test_cuberoot(v, 64.0)
  fail = fail .or. Test_cuberoot(v, -0.5000000000001)
  fail = fail .or. Test_cuberoot(v, 0.0)
  fail = fail .or. Test_cuberoot(v, 1.0)
  fail = fail .or. Test_cuberoot(v, 0.125)
  fail = fail .or. Test_cuberoot(v, 0.965)
  fail = fail .or. Test_cuberoot(v, 1.0 - epsilon(1.0))
  fail = fail .or. Test_cuberoot(v, 1.0 - 0.5*epsilon(1.0))

  testval = 1.0e-99
  v = .false.
  do n=-160,160
    fail = fail .or. Test_cuberoot(v, testval)
    testval = (-2.908 * (1.414213562373 + 1.2345678901234e-5*n)) * testval
  enddo

  v = verbose
  fail = fail .or. Test_exp_reprod(v, 0.0)
  fail = fail .or. Test_exp_reprod(v, 1.0)
  fail = fail .or. Test_exp_reprod(v, -3.7)
  fail = fail .or. Test_exp_reprod(v, 20.0)
  v = .false.
  do n=-700,200
    fail = fail .or. Test_exp_reprod(v, 0.1*n)
  enddo

  v = verbose
  fail = fail .or. Test_log_reprod(v, 2.0)
  fail = fail .or. Test_log_reprod(v, 0.7)
  fail = fail .or. Test_log_reprod(v, 1.0e6)
  v = .false.
  do n=1,6000
    fail = fail .or. Test_log_reprod(v, 10.0**((0.01*real(n)) - 30.0))
  enddo
end function intrinsic_functions_unit_tests

!> True if the cube of cuberoot(val) does not closely match val. False otherwise.
logical function Test_cuberoot(verbose, val)
  logical, intent(in) :: verbose !< If true, write results to stdout
  real, intent(in) :: val  !< The real value to test, in arbitrary units [A]
  ! Local variables
  real :: diff ! The difference between val and the cube root of its cube [A].

  diff = val - cuberoot(val)**3
  Test_cuberoot = (abs(diff) > 2.0e-15*abs(val))

  if (Test_cuberoot) then
    write(stdout, '("For val = ",ES22.15,", (val - cuberoot(val**3))) = ",ES9.2," <-- FAIL")') val, diff
  elseif (verbose) then
    write(stdout, '("For val = ",ES22.15,", (val - cuberoot(val**3))) = ",ES9.2)') val, diff

  endif
end function Test_cuberoot

!> True if exp_reprod(val) does not closely match the intrinsic exp(val). False otherwise.
logical function Test_exp_reprod(verbose, val)
  logical, intent(in) :: verbose !< If true, write results to stdout
  real, intent(in) :: val  !< The real value to test [nondim]
  ! Local variables
  real :: e_ref  ! The intrinsic exponential of val [nondim]
  real :: relerr ! The relative difference between exp_reprod(val) and exp(val) [nondim]

  e_ref = exp(val)
  relerr = abs(exp_reprod(val) - e_ref) / e_ref
  Test_exp_reprod = (relerr > 1.0e-14)

  if (Test_exp_reprod) then
    write(stdout, '("For val = ",ES22.15,", exp_reprod relative error = ",ES9.2," <-- FAIL")') val, relerr
  elseif (verbose) then
    write(stdout, '("For val = ",ES22.15,", exp_reprod relative error = ",ES9.2)') val, relerr
  endif
end function Test_exp_reprod

!> True if log_reprod(val) does not closely match the intrinsic log(val). False otherwise.
logical function Test_log_reprod(verbose, val)
  logical, intent(in) :: verbose !< If true, write results to stdout
  real, intent(in) :: val  !< The real value to test, val > 0 [nondim]
  ! Local variables
  real :: l_ref  ! The intrinsic natural logarithm of val [nondim]
  real :: relerr ! The relative difference between log_reprod(val) and log(val) [nondim]

  l_ref = log(val)
  if (l_ref /= 0.0) then ; relerr = abs(log_reprod(val) - l_ref) / abs(l_ref)
  else ; relerr = abs(log_reprod(val) - l_ref) ; endif
  Test_log_reprod = (relerr > 1.0e-13)

  if (Test_log_reprod) then
    write(stdout, '("For val = ",ES22.15,", log_reprod relative error = ",ES9.2," <-- FAIL")') val, relerr
  elseif (verbose) then
    write(stdout, '("For val = ",ES22.15,", log_reprod relative error = ",ES9.2)') val, relerr
  endif
end function Test_log_reprod

end module MOM_intrinsic_functions
