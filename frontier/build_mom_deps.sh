#!/bin/bash
###############################################################################
# build_mom_deps.sh
#
# Builds the MOM6 dependency stack with the AMD LLVM compilers (amdclang /
# amdclang++ / amdflang), in order:
#
#     1. MPICH            2. HDF5 (parallel)    3. netCDF-C    4. netCDF-Fortran
#
# Everything is installed into $MOM_ROOT/install_mom_deps_afar (override with PREFIX).
# Run fetch_sources.sh first. Compiler: $ROCM_PATH (default $AFAR, from afar_env.sh).
#
# Usage:
#     ./build_mom_deps.sh                 # build all four, in order
#     ./build_mom_deps.sh hdf5            # build only hdf5 (and later stages
#     ./build_mom_deps.sh netcdf-c        #   are NOT run)
#     ./build_mom_deps.sh mpich hdf5      # build a subset, in the order given
#     NJOBS=64 ./build_mom_deps.sh        # override parallelism
#     CLEAN=1  ./build_mom_deps.sh        # wipe build dirs + stamps first
#
# Completed stages leave a stamp in install_mom_deps/.stamps and are skipped on
# re-run; delete the stamp (or use CLEAN=1) to force a rebuild.
#
# NOTE: run this on a compute node (or at least accept the load) -- the default
#       is make -j128.
###############################################################################
set -euo pipefail

#------------------------------------------------------------------------------
# Paths
#------------------------------------------------------------------------------
# MOM_ROOT holds the source trees (see fetch_sources.sh) and receives the install.
ROOT="${MOM_ROOT:?set MOM_ROOT (the directory with the extracted sources; see fetch_sources.sh)}"
PREFIX="${PREFIX:-$ROOT/install_mom_deps_afar}"
BUILD="${BUILD:-$ROOT/build_mom_deps_afar}"          # out-of-source build trees
LOGS="${LOGS:-$ROOT/logs_mom_deps_afar}"
STAMPS="$PREFIX/.stamps"

MPICH_SRC="$ROOT/mpich-5.0.1"
HDF5_SRC="$ROOT/hdf5-2.2.0"
NCC_SRC="$ROOT/netcdf-c-4.10.1"
NCF_SRC="$ROOT/netcdf-fortran-4.6.4"

MPICH_VER="5.0.1"
MPICH_URL="https://www.mpich.org/static/downloads/${MPICH_VER}/mpich-${MPICH_VER}.tar.gz"

NJOBS="${NJOBS:-128}"

mkdir -p "$PREFIX" "$BUILD" "$LOGS" "$STAMPS"

#------------------------------------------------------------------------------
# Compilers -- AMD LLVM (amdflang is the new LLVM Flang, not the old classic)
#------------------------------------------------------------------------------
: "${ROCM_PATH:=${AFAR:?set AFAR or ROCM_PATH to the AFAR install}}"
export ROCM_PATH
export PATH="$ROCM_PATH/bin:$PATH"
export LD_LIBRARY_PATH="$ROCM_PATH/lib:${LD_LIBRARY_PATH:-}"

export CC="$(command -v amdclang)"
export CXX="$(command -v amdclang++)"
export FC="$(command -v amdflang)"
export F77="$FC"
export F90="$FC"

# Common optimisation flags. -fPIC everywhere so the shared libs link cleanly.
export CFLAGS="${CFLAGS:--O2 -fPIC}"
export CXXFLAGS="${CXXFLAGS:--O2 -fPIC}"
export FFLAGS="${FFLAGS:--O2 -fPIC}"
export FCFLAGS="${FCFLAGS:-$FFLAGS}"

# Make the stack self-referential at runtime: no LD_LIBRARY_PATH needed later.
export LDFLAGS="-L$PREFIX/lib -Wl,-rpath,$PREFIX/lib ${LDFLAGS:-}"
export CPPFLAGS="-I$PREFIX/include ${CPPFLAGS:-}"

# Pick up the freshly built MPICH/HDF5/netCDF as each stage completes.
export PATH="$PREFIX/bin:$PATH"
export LD_LIBRARY_PATH="$PREFIX/lib:$LD_LIBRARY_PATH"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

#------------------------------------------------------------------------------
# Helpers
#------------------------------------------------------------------------------
say()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die()  { printf '\n\033[1;31m!!! %s\033[0m\n' "$*" >&2; exit 1; }

done_stamp()  { [[ -f "$STAMPS/$1" ]]; }
mark_done()   { touch "$STAMPS/$1"; }

# run <logname> <cmd...>  -- tee to a log so failures are diagnosable
run() {
    local log="$LOGS/$1.log"; shift
    say "$* "
    echo "    (log: $log)"
    "$@" 2>&1 | tee -a "$log"
    return "${PIPESTATUS[0]}"
}

# fix_libtool_flang <dir>
# libtool 2.4.6 predates LLVM Flang: amdflang is not detected as GNU Fortran and
# matches no vendor case in _LT_COMPILER_PIC, so the FC/F77 tags end up with
#     wl=""   pic_flag=""
# Every linker flag is then interpolated bare ($wl--whole-archive, $wl-soname),
# and flang-23 rejects them:
#     flang-23: error: unknown argument: '--whole-archive'
#     flang-23: error: unknown argument: '-soname'
# Patch the generated libtool scripts so $wl expands to -Wl, again.
fix_libtool_flang() {
    local dir="$1" n=0 lt tag
    while IFS= read -r -d '' lt; do
        grep -q 'BEGIN LIBTOOL TAG CONFIG' "$lt" || continue
        for tag in FC F77; do
            sed -i "/^# ### BEGIN LIBTOOL TAG CONFIG: ${tag}\$/,/^# ### END LIBTOOL TAG CONFIG: ${tag}\$/{
                s|^wl=\"\"\$|wl=\"-Wl,\"|
                s|^pic_flag=\"\"\$|pic_flag=\" -fPIC -DPIC\"|
            }" "$lt"
        done
        n=$((n+1))
    done < <(find "$dir" -name libtool -type f -print0)
    say "patched $n libtool script(s) for amdflang (FC/F77: wl=-Wl,)"
}

if [[ "${CLEAN:-0}" == "1" ]]; then
    say "CLEAN=1: removing build trees, logs and stamps"
    rm -rf "$BUILD" "$LOGS" "$STAMPS"
    mkdir -p "$BUILD" "$LOGS" "$STAMPS"
fi

#------------------------------------------------------------------------------
# 1. MPICH
#------------------------------------------------------------------------------
build_mpich() {
    if done_stamp mpich; then say "MPICH already built -- skipping"; return; fi
    say "Building MPICH $MPICH_VER"

    # The extracted GitHub tree has no ./configure (it is a source checkout, not
    # a release tarball). Prefer a release tarball; fall back to autogen.sh.
    if [[ ! -x "$MPICH_SRC/configure" ]]; then
        # NB: the local v${MPICH_VER}.tar.gz is the *GitHub* tarball -- it ships no
        # ./configure either, so it is not a substitute for the release tarball.
        local tb="$ROOT/mpich-${MPICH_VER}.tar.gz"
        if [[ ! -f "$tb" ]]; then
            say "No ./configure in $MPICH_SRC -- fetching release tarball"
            curl -fL --retry 3 -o "$tb.part" "$MPICH_URL" && mv "$tb.part" "$tb" || rm -f "$tb.part"
        fi
        if [[ -f "$tb" ]]; then
            # Extract beside, NOT on top of, the existing GitHub checkout.
            say "Extracting $tb -> $ROOT/mpich-${MPICH_VER}-release"
            rm -rf "$ROOT/mpich-${MPICH_VER}-release"
            mkdir -p "$ROOT/mpich-${MPICH_VER}-release"
            tar -xzf "$tb" -C "$ROOT/mpich-${MPICH_VER}-release" --strip-components=1
            MPICH_SRC="$ROOT/mpich-${MPICH_VER}-release"
        else
            say "Falling back to autogen.sh (needs autoconf>=2.71, automake>=1.16, libtool>=2.4.6)"
            ( cd "$MPICH_SRC" && ./autogen.sh ) 2>&1 | tee "$LOGS/mpich-autogen.log"
            [[ -x "$MPICH_SRC/configure" ]] || die \
"MPICH has no ./configure and autogen.sh failed.
 Fix: download the release tarball by hand, e.g.
     curl -LO $MPICH_URL
     tar xzf mpich-${MPICH_VER}.tar.gz
 (note: the v${MPICH_VER}.tar.gz you already have is the GitHub tarball, which
  contains no ./configure -- you need the mpich.org release tarball.)
 Or install newer autotools and retry autogen.sh, e.g.
     conda create -n autotools -c conda-forge autoconf automake libtool m4
     conda activate autotools
 then re-run this script."
        fi
    fi

    local bd="$BUILD/mpich"; mkdir -p "$bd"
    ( cd "$bd" && run mpich-configure "$MPICH_SRC/configure" \
        --prefix="$PREFIX"                                    \
        --enable-shared                                       \
        --enable-fortran=all                                  \
        --enable-cxx                                          \
        --enable-fast=O2                                      \
        --disable-dependency-tracking                          \
        --with-device=ch4:ofi                                 \
        FFLAGS="$FFLAGS -fPIC"                                \
        FCFLAGS="$FCFLAGS -fPIC" )
    fix_libtool_flang "$bd"
    # For Slingshot, point at the Cray libfabric instead of the embedded one:
    #   --with-libfabric=/opt/cray/libfabric/<version>

    ( cd "$bd" && run mpich-make make -j"$NJOBS" )
    ( cd "$bd" && run mpich-install make install )

    mark_done mpich
    say "MPICH installed -> $PREFIX"
}

#------------------------------------------------------------------------------
# 2. HDF5 (parallel, with Fortran) -- CMake only; HDF5 2.x dropped autotools
#------------------------------------------------------------------------------
build_hdf5() {
    if done_stamp hdf5; then say "HDF5 already built -- skipping"; return; fi
    say "Building HDF5 (parallel + Fortran)"

    [[ -x "$PREFIX/bin/mpicc" ]] || die "mpicc not found in $PREFIX/bin -- build MPICH first"

    local bd="$BUILD/hdf5"; rm -rf "$bd"; mkdir -p "$bd"
    ( cd "$bd" && run hdf5-cmake cmake "$HDF5_SRC"                     \
        -DCMAKE_INSTALL_PREFIX="$PREFIX"                               \
        -DCMAKE_BUILD_TYPE=Release                                     \
        -DCMAKE_C_COMPILER="$PREFIX/bin/mpicc"                         \
        -DCMAKE_Fortran_COMPILER="$PREFIX/bin/mpifort"                 \
        -DCMAKE_C_FLAGS="$CFLAGS"                                      \
        -DCMAKE_Fortran_FLAGS="$FCFLAGS"                               \
        -DCMAKE_INSTALL_RPATH="$PREFIX/lib"                            \
        -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON                            \
        -DBUILD_SHARED_LIBS=ON                                         \
        -DBUILD_STATIC_LIBS=ON                                         \
        -DBUILD_TESTING=OFF                                            \
        -DHDF5_ENABLE_PARALLEL=ON                                      \
        -DHDF5_BUILD_FORTRAN=ON                                        \
        -DHDF5_BUILD_HL_LIB=ON                                         \
        -DHDF5_BUILD_CPP_LIB=OFF                                       \
        -DHDF5_BUILD_JAVA=OFF                                          \
        -DHDF5_BUILD_EXAMPLES=OFF                                      \
        -DHDF5_BUILD_TOOLS=ON                                          \
        -DHDF5_ENABLE_Z_LIB_SUPPORT=ON                                 \
        -DHDF5_ENABLE_ZLIB_SUPPORT=ON                                  \
        -DHDF5_ENABLE_SZIP_SUPPORT=OFF                                 \
        -DHDF5_INSTALL_LIB_DIR=lib                                     \
        -DHDF5_INSTALL_INCLUDE_DIR=include                             \
        -DHDF5_INSTALL_BIN_DIR=bin )
    # (the two Z_LIB/ZLIB spellings differ across HDF5 releases; the unused one
    #  is only a CMake warning. Add -DHDF5_ENABLE_ZLIB_SUPPORT=OFF if no zlib.)

    ( cd "$bd" && run hdf5-make make -j"$NJOBS" )
    ( cd "$bd" && run hdf5-install make install )

    mark_done hdf5
    say "HDF5 installed -> $PREFIX"
}

#------------------------------------------------------------------------------
# 3. netCDF-C
#------------------------------------------------------------------------------
build_netcdf_c() {
    if done_stamp netcdf-c; then say "netCDF-C already built -- skipping"; return; fi
    say "Building netCDF-C"

    [[ -f "$PREFIX/include/hdf5.h" ]] || die "hdf5.h not found in $PREFIX/include -- build HDF5 first"

    local bd="$BUILD/netcdf-c"; mkdir -p "$bd"
    ( cd "$bd" && run netcdf-c-configure "$NCC_SRC/configure" \
        --prefix="$PREFIX"                                    \
        --enable-shared                                       \
        --enable-static                                       \
        --enable-netcdf-4                                     \
        --enable-parallel4                                    \
        --disable-dap                                         \
        --disable-byterange                                   \
        --disable-libxml2                                     \
        --disable-nczarr                                      \
        --disable-dependency-tracking                          \
        CC="$PREFIX/bin/mpicc"                                \
        CPPFLAGS="-I$PREFIX/include"                          \
        LDFLAGS="-L$PREFIX/lib -Wl,-rpath,$PREFIX/lib" )
    fix_libtool_flang "$bd"

    ( cd "$bd" && run netcdf-c-make make -j"$NJOBS" )
    ( cd "$bd" && run netcdf-c-install make install )

    mark_done netcdf-c
    say "netCDF-C installed -> $PREFIX"
}

#------------------------------------------------------------------------------
# 4. netCDF-Fortran  (this is the one that must be built with amdflang)
#------------------------------------------------------------------------------
build_netcdf_fortran() {
    if done_stamp netcdf-fortran; then say "netCDF-Fortran already built -- skipping"; return; fi
    say "Building netCDF-Fortran"

    [[ -x "$PREFIX/bin/nc-config" ]] || die "nc-config not found in $PREFIX/bin -- build netCDF-C first"

    local bd="$BUILD/netcdf-fortran"; mkdir -p "$bd"
    ( cd "$bd" && run netcdf-fortran-configure "$NCF_SRC/configure" \
        --prefix="$PREFIX"                                          \
        --enable-shared                                             \
        --enable-static                                             \
        --disable-dependency-tracking                                \
        CC="$PREFIX/bin/mpicc"                                      \
        FC="$PREFIX/bin/mpifort"                                    \
        F77="$PREFIX/bin/mpifort"                                   \
        CPPFLAGS="-I$PREFIX/include"                                \
        FCFLAGS="$FCFLAGS -I$PREFIX/include"                        \
        FFLAGS="$FFLAGS -I$PREFIX/include"                          \
        LDFLAGS="-L$PREFIX/lib -Wl,-rpath,$PREFIX/lib"              \
        LIBS="-lnetcdf" )
    fix_libtool_flang "$bd"

    ( cd "$bd" && run netcdf-fortran-make make -j"$NJOBS" )
    ( cd "$bd" && run netcdf-fortran-install make install )

    mark_done netcdf-fortran
    say "netCDF-Fortran installed -> $PREFIX"
}

#------------------------------------------------------------------------------
# Driver
#------------------------------------------------------------------------------
say "prefix   : $PREFIX"
say "compilers: CC=$CC  CXX=$CXX  FC=$FC"
say "jobs     : -j$NJOBS"

STAGES=("$@")
[[ ${#STAGES[@]} -eq 0 ]] && STAGES=(mpich hdf5 netcdf-c netcdf-fortran)

for s in "${STAGES[@]}"; do
    case "$s" in
        mpich)          build_mpich          ;;
        hdf5)           build_hdf5           ;;
        netcdf-c)       build_netcdf_c       ;;
        netcdf-fortran) build_netcdf_fortran ;;
        *) die "unknown stage '$s' (mpich|hdf5|netcdf-c|netcdf-fortran)" ;;
    esac
done

#------------------------------------------------------------------------------
# Environment file for the MOM6 build
#------------------------------------------------------------------------------
cat > "$PREFIX/env.sh" <<EOF
# source this before configuring/building MOM6
export ROCM_PATH=$ROCM_PATH
export MOM_DEPS=$PREFIX
export PATH=\$MOM_DEPS/bin:\$ROCM_PATH/bin:\$PATH
export LD_LIBRARY_PATH=\$MOM_DEPS/lib:\$ROCM_PATH/lib:\$LD_LIBRARY_PATH
export PKG_CONFIG_PATH=\$MOM_DEPS/lib/pkgconfig:\$PKG_CONFIG_PATH
export MPI_ROOT=\$MOM_DEPS
export HDF5_ROOT=\$MOM_DEPS
export NETCDF_ROOT=\$MOM_DEPS
export NETCDF=\$MOM_DEPS
export NETCDF_DIR=\$MOM_DEPS
export CC=\$MOM_DEPS/bin/mpicc
export CXX=\$MOM_DEPS/bin/mpicxx
export FC=\$MOM_DEPS/bin/mpifort
export F77=\$MOM_DEPS/bin/mpifort
EOF

say "All requested stages complete."
echo "    prefix : $PREFIX"
echo "    env    : source $PREFIX/env.sh   # before building MOM6"
echo "    logs   : $LOGS"
