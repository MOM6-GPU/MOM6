#!/bin/bash
# Needs an Aurora GPU compute node.
cd "$(dirname "$0")" ; mkdir -p build && cd build
for opt in -O0 -O3; do
  echo "=== ifx $opt"
  ifx $opt -qopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent ../reproducer.F90 -o r$opt.x > c$opt.log 2>&1 \
    || { echo "compile FAILED"; grep -m3 error c$opt.log; continue; }
  LIBOMPTARGET_LEVEL_ZERO_STAGING_BUFFER_SIZE=0 ./r$opt.x
done
