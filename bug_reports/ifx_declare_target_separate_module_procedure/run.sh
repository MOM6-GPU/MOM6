#!/bin/bash
# Build the reproducer with the three directive placements.  For each build that
# compiles, report whether the device code defines and/or calls f (parent_mp_f_),
# which shows the run-time link failure without a GPU.  Run on an Aurora compute
# node to execute the binaries.
cd "$(dirname "$0")"
mkdir -p build && cd build
OFFLOAD="-qopenmp -fopenmp-targets=spir64"
TOOLS=$(dirname "$(readlink -f "$(which ifx)")")/compiler
ifx --version | head -1

build_run() {
  local name=$1; shift
  echo "=== $name: ifx $* reproducer.F90"
  if ! ifx "$@" -c ../reproducer.F90 -o "$name.o" > "$name.log" 2>&1; then
    echo "compile: FAILED (see build/$name.log)"; grep -m1 "error #" "$name.log"; return
  fi
  echo "compile: OK $(grep -o 'warning #5476' "$name.log" | head -1)"
  if "$TOOLS/clang-offload-bundler" -type=o -targets=openmp-spir64 -input="$name.o" \
       -output="$name.dev" -unbundle 2>/dev/null && \
     "$TOOLS/llvm-spirv" -spirv-ext=+all -spirv-text "$name.dev" -o "$name.spt" 2>/dev/null; then
    echo "device code: defines f: $(grep -c 'LinkageAttributes "parent_mp_f_" Export' "$name.spt")," \
         "calls f: $(grep -c 'LinkageAttributes "parent_mp_f_" Import' "$name.spt")"
  fi
  ifx "$@" "$name.o" -o "$name.x" >> "$name.log" 2>&1 && ./"$name.x" 2>&1 | grep -m2 "PASS\|FAIL\|No images\|link failed"
}

build_run both       -O3 $OFFLOAD                 # expected: error #8682
build_run iface_only -O3 $OFFLOAD -DIFACE_ONLY    # expected: calls f, never defines it -> GPU load fails
build_run workaround -O3 $OFFLOAD -DWORKAROUND    # expected: defines f; PASS on a GPU node
