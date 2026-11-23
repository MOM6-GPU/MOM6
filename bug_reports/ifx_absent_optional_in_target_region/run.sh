#!/bin/bash
# The compile-time warning shows on any node; the crash needs an Aurora GPU compute node.
cd "$(dirname "$0")"
mkdir -p build && cd build
F="-O2 -qopenmp -fopenmp-targets=spir64"
ifx --version | head -1
for v in bug workaround; do
  D=""; [ $v = workaround ] && D=-DWORKAROUND
  echo "=== $v: ifx $F $D reproducer.F90"
  ifx $F $D ../reproducer.F90 -o $v.x > $v.log 2>&1 || { echo "compile FAILED"; continue; }
  echo "compile: OK $(grep -o 'warning #5590[^.]*' $v.log | head -1)"
  ./$v.x 2>&1 | grep -m2 "PASS\|FAIL\|No images\|SIGSEGV\|signal"; echo "  exit status: ${PIPESTATUS[0]}"
done
