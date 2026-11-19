#!/bin/bash
# Build and run the reproducer in three configurations.
# Run on an Aurora compute node so the offload binaries can execute on the GPU
# (on a login node they abort with "No images found compatible with the
# installed hardware", which is unrelated to this bug).
cd "$(dirname "$0")"
mkdir -p build && cd build
OFFLOAD="-qopenmp -fopenmp-targets=spir64"
ifx --version | head -1

build_run() {
  local name=$1; shift
  echo "=== $name: ifx $* reproducer.F90"
  if ifx "$@" ../reproducer.F90 -o "$name.x" > "$name.log" 2>&1; then
    echo "compile: OK"; ./"$name.x"
  else
    echo "compile: FAILED (see build/$name.log)"
    grep -m1 "error #" "$name.log"
  fi
}

build_run bug_offload -O3 $OFFLOAD                # expected: ICE (error #5623)
build_run bug_host    -O3 -qopenmp                # expected: ICE (error #5623)
build_run workaround  -O3 $OFFLOAD -DWORKAROUND   # expected: compiles, PASS
build_run workaround_host -O3 -qopenmp -DWORKAROUND # expected: compiles, PASS
