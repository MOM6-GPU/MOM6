# Source this before building or running MOM6 on Frontier with the AMD AFAR flang drop.
#
#   MOM_ROOT   directory holding the toolchain and dependency installs
#              (default: four levels above this file, i.e. the dir containing MOM6-examples)
#   AFAR       AFAR install (default: $MOM_ROOT/therock-afar-24.4.0-multiarch-10.3.0-a71da8f)
#   MOM_DEPS   MPICH/HDF5/netCDF built with AFAR (default: $MOM_ROOT/install_mom_deps_afar)
#
# Self-contained: does NOT load the rocm module; the drop ships its own HSA/HIP runtime.

_frontier_dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
export MOM_ROOT="${MOM_ROOT:-$(cd "$_frontier_dir/../../../.." && pwd)}"
export AFAR="${AFAR:-$MOM_ROOT/therock-afar-24.4.0-multiarch-10.3.0-a71da8f}"
export MOM_DEPS="${MOM_DEPS:-$MOM_ROOT/install_mom_deps_afar}"
export ROCM_PATH=$AFAR

export PATH=$MOM_DEPS/bin:$AFAR/bin:$PATH
export LD_LIBRARY_PATH=$MOM_DEPS/lib:$AFAR/lib/llvm/lib:$AFAR/lib/llvm/lib/x86_64-unknown-linux-gnu:$AFAR/lib:${LD_LIBRARY_PATH:-}

# The MPICH wrappers in MOM_DEPS were built with this compiler; pin them to it anyway.
export MPICH_FC=$AFAR/bin/amdflang MPICH_CC=$AFAR/bin/amdclang
unset _frontier_dir
