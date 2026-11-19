#!/bin/bash
# Must run on an Aurora GPU compute node: the bug is in what the offload runtime copies
# back to the host, so a host-only build or a login node cannot show it.
cd "$(dirname "$0")"
mkdir -p build && cd build
ifx --version | head -1
for opt in -O0 -O3; do
  echo "=== ifx $opt -qopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent"
  ifx $opt -qopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent ../reproducer.F90 -o r$opt.x > c$opt.log 2>&1 \
    || { echo "compile FAILED (see build/c$opt.log)"; continue; }
  ./r$opt.x
done
