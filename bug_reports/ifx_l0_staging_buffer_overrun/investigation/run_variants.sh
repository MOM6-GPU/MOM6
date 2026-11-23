#!/bin/bash
# Needs an Aurora GPU compute node.  Builds each variant and runs it with the default
# runtime settings, with LIBOMPTARGET_LEVEL_ZERO_COMMAND_MODE=sync, with
# LIBOMPTARGET_LEVEL_ZERO_STAGING_BUFFER_SIZE=0 and (full variant only) with LIBOMPTARGET_DEBUG=1.
# Usage: ./run.sh                       (the variants in README.md)
#        VARIANTS="full A:B" ./run.sh   (chosen variants; A:B means -DA -DB)
cd "$(dirname "$0")"
mkdir -p build && cd build
F="-O3 -qopenmp -fopenmp-targets=spir64"
ifx --version | head -1
build() { ifx $F "$@" ../reproducer_variants.F90 -o "$name.x" > "$name.log" 2>&1 || { echo "compile FAILED ($name)"; return 1; }; }
runit() { # $1 label, rest: env settings
  local label=$1; shift
  printf '  %-12s ' "$label"; env "$@" ./$name.x 2>&1 | grep -v "^omptarget\|^PluginInterface\|^TARGET\|^OMPT" | tr '\n' ' '; echo
}
DEFAULT="full NO_PARENT NO_ALLOCS NO_PAD WORKAROUND UPDATE_FIRST SCALAR_UPDATE ALLOC_UPDATE_MAP"
DEFAULT="$DEFAULT ALLOC_UPDATE_MAP:PARENT_ALLOCS ALLOC_UPDATE_MAP:PARENT_MANY"
DEFAULT="$DEFAULT ALLOC_UPDATE_MAP:PARENT_MANY:BYTE_UPDATE ALLOC_UPDATE_MAP:NPAR=20 ALLOC_UPDATE_MAP:NPAR=22"
for v in ${VARIANTS:-$DEFAULT}; do
  name=${v//:/_}; name=${name//=/}; D=""; [ $v != full ] && D="-D${v//:/ -D}"
  echo "=== variant $v ($D)"
  build $D || continue
  runit default    X=0
  runit sync       LIBOMPTARGET_LEVEL_ZERO_COMMAND_MODE=sync
  runit nostaging  LIBOMPTARGET_LEVEL_ZERO_STAGING_BUFFER_SIZE=0
  [ $v = full ] && runit debug LIBOMPTARGET_DEBUG=1
done
