#!/bin/bash
# Needs an Aurora GPU compute node.  Builds the reproducer, the workaround and the
# small-structure control, and runs each with the default runtime settings and with the
# two Level Zero settings that avoid the bug.
cd "$(dirname "$0")"
mkdir -p build && cd build
F="-O3 -qopenmp -fopenmp-targets=spir64"
ifx --version | head -1
for v in bug WORKAROUND NO_PAD; do
  D=""; [ $v != bug ] && D=-D$v
  ifx $F $D ../reproducer.F90 -o $v.x > $v.log 2>&1 || { echo "compile FAILED ($v)"; continue; }
  for e in DEFAULT=1 LIBOMPTARGET_LEVEL_ZERO_COMMAND_MODE=sync LIBOMPTARGET_LEVEL_ZERO_STAGING_BUFFER_SIZE=0; do
    printf '%-11s %-46s ' "$v" "$e"; env $e ./$v.x 2>&1 | grep "wrong device reads"
  done
done
