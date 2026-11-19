#!/bin/bash
# Needs an Aurora GPU compute node.
cd "$(dirname "$0")"
mkdir -p build && cd build
F="-qopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent"
ifx --version | head -1
for opt in -O0 -O3; do for v in bug workaround; do
  D=""; [ $v = workaround ] && D=-DWORKAROUND
  echo "=== $v: ifx $opt $F $D"
  ifx $opt $F $D ../reproducer.F90 -o $v$opt.x > $v$opt.log 2>&1 || { echo "compile FAILED"; continue; }
  grep -o "warning #5590[^.]*" $v$opt.log | sort -u
  ./$v$opt.x
done; done
