#!/bin/bash
# Needs an Aurora GPU compute node.
cd "$(dirname "$0")" ; mkdir -p build && cd build
F="-qopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent"
for v in "" -DWORKAROUND; do for opt in -O0 -O3; do
  echo "=== ifx $opt $v"
  ifx $opt $F $v ../reproducer.F90 -o r$opt$v.x > c$opt$v.log 2>&1 || { echo "compile FAILED"; grep -m3 error c$opt$v.log; continue; }
  LIBOMPTARGET_LEVEL_ZERO_STAGING_BUFFER_SIZE=0 ./r$opt$v.x
done; done
