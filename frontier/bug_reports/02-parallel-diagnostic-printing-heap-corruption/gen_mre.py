# Generates mre_parallel_warning_print.f90: N procedures, each with a standalone `!$omp loop` nested
# in `!$omp target` (flang warns and rewrites it to simd, printing the op), reading through a cycle
# of T derived types. The loop-conversion pass runs per function on MLIR's thread pool.
import sys
T = int(sys.argv[1]) if len(sys.argv) > 1 else 40
N = int(sys.argv[2]) if len(sys.argv) > 2 else 64
o = ["module m", "  implicit none"]
for t in range(T):
    o += [f"  type :: t{t}", f"    type(t{(t+1)%T}), pointer :: p => null()",
          "    real, allocatable :: v(:,:)", "  end type"]
o.append("contains")
for n in range(N):
    o += [f"  subroutine s{n}(x, a, ni, nj, nk)",
          "    type(t0), intent(in) :: x", "    integer, intent(in) :: ni, nj, nk",
          "    real, intent(inout) :: a(ni,nj,nk)", "    integer :: i, j, k",
          "    !$omp target map(tofrom: a)", "    do k = 1, nk",
          "      !$omp loop collapse(2)", "      do j = 1, nj ; do i = 1, ni",
          "        a(i,j,k) = a(i,j,k) + x%p%v(i,j)", "      enddo ; enddo",
          "    enddo", "    !$omp end target", f"  end subroutine s{n}"]
o.append("end module m")
open("mre_parallel_warning_print.f90", "w").write("\n".join(o) + "\n")
