#!/bin/bash
# Build the reproducer ahead-of-time for PVC (fails at link time on the login node),
# and JIT builds that must be run on a GPU node to see the runtime failure.
cd "$(dirname "$0")"
mkdir -p build && cd build
DC="-qopenmp -fopenmp-target-do-concurrent"
AOT="-fopenmp-targets=spir64_gen -Xopenmp-target-backend -device -Xopenmp-target-backend pvc"
JIT="-fopenmp-targets=spir64"
ifx --version | head -1

build_run() {
  local name=$1; shift
  echo "=== $name: ifx $* reproducer.F90"
  if ifx "$@" ../reproducer.F90 -o "$name.x" > "$name.log" 2>&1; then
    echo "compile+link: OK"; ./"$name.x" 2>&1 | grep -m3 "PASS\|FAIL\|exceeds\|No images"
  else
    echo "compile+link: FAILED (see build/$name.log)"
    grep -m1 "exceeds limit" "$name.log"
  fi
}

build_run bug_aot        -O3 $DC $AOT                # expected: link fails, "exceeds limit"
build_run workaround_aot -O3 $DC $AOT -DWORKAROUND   # expected: links (runs on a GPU node)
build_run bug_jit        -O3 $DC $JIT                # expected on GPU: Level Zero "exceeds limit"
build_run workaround_jit -O3 $DC $JIT -DWORKAROUND   # expected on GPU: PASS
