#!/bin/bash
# Needs an Aurora GPU compute node.  Builds at -O0 and -O3.
cd "$(dirname "$0")"
mkdir -p build && cd build
ifx --version | head -1
for opt in -O0 -O3 "-O3 -fp-model precise"; do
  echo "=== ifx $opt -qopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent"
  ifx $opt -qopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent ../reproducer.F90 -o "r${opt// /_}.x" > "c${opt// /_}.log" 2>&1 \
    || { echo "compile FAILED (see build/c${opt// /_}.log)"; grep -m2 "error" "c${opt// /_}.log"; continue; }
  grep -m3 "warning" "c${opt// /_}.log"
  "./r${opt// /_}.x"
done
