#!/bin/bash
# Needs an Aurora GPU compute node.  Prints the time per kernel launch for each variant,
# then the number of map entries the runtime processes for one launch of each kernel.
cd "$(dirname "$0")" ; mkdir -p build && cd build
F="-g -O3 -qopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent"
export LIBOMPTARGET_LEVEL_ZERO_STAGING_BUFFER_SIZE=0
ifx --version | head -1
ifx $F ../reproducer.F90 -o r.x > c.log 2>&1 || { echo "compile FAILED"; grep -m3 error c.log; exit 1; }
ifx $F -fopenmp-do-concurrent-maptype-modifier=present ../reproducer.F90 -o rp.x > cp.log 2>&1 \
  || { echo "compile FAILED (maptype present)"; grep -m3 error cp.log; }
echo "=== $F" ; ./r.x
echo "=== same, plus -fopenmp-do-concurrent-maptype-modifier=present" ; [ -x rp.x ] && ./rp.x
echo "=== map entries per launch (LIBOMPTARGET_INFO=1): count, source line, arguments"
LIBOMPTARGET_INFO=1 ./r.x 2>&1 | grep -a "Entering OpenMP kernel" \
  | sed 's/.*kernel at \([^ ]*\) with \([0-9]*\) arguments.*/\1 \2/' | sort -t: -k2 -n | uniq -c
