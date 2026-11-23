#!/bin/bash
# Needs an Aurora GPU compute node (the host-fallback and no-OpenMP runs work anywhere).
cd "$(dirname "$0")" ; mkdir -p build && cd build
F="-qopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent"
echo "=== ifx -O3 without OpenMP" ; ifx -O3 ../reproducer.F90 -o serial.x > cs.log 2>&1 && ./serial.x
for opt in -O0 -O3; do
  ifx $opt $F ../reproducer.F90 -o r$opt.x > c$opt.log 2>&1 || { echo "compile FAILED"; grep -m3 error c$opt.log; continue; }
  echo "=== ifx $opt offload, OMP_TARGET_OFFLOAD=DISABLED" ; OMP_TARGET_OFFLOAD=DISABLED ./r$opt.x
  echo "=== ifx $opt offload, on the GPU" ; LIBOMPTARGET_LEVEL_ZERO_STAGING_BUFFER_SIZE=0 ./r$opt.x
done
