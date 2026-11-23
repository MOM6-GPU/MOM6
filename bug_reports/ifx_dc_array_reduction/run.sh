#!/bin/bash
# Needs an Aurora GPU compute node.
cd "$(dirname "$0")" ; mkdir -p build && cd build
F="-qopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent"
echo "=== -DCASE3 compile check: $(ifx -O3 $F -DCASE3 ../reproducer.F90 -o case3.x > case3.log 2>&1 && echo compiles || grep -o 'error #[0-9]*' case3.log | head -1)"
for opt in -O0 -O3; do
  echo "=== ifx $opt  (columns: s(1) got, s(1) expected, s(nk) error)"
  ifx $opt $F ../reproducer.F90 -o r$opt.x > c$opt.log 2>&1 || { echo "compile FAILED"; grep -m3 error c$opt.log; continue; }
  LIBOMPTARGET_LEVEL_ZERO_STAGING_BUFFER_SIZE=0 ./r$opt.x
done
