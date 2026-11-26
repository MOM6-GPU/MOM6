#!/bin/bash
# Needs a GPU. From a login node: RUN="srun --jobid=<id> --overlap -n1 --gpus=1" ./run.sh
cd "$(dirname "$0")"; source ../../afar_env.sh; RUN=${RUN:-}
for f in mre_array_reduce workaround_omp; do
  amdflang -O2 -fopenmp --offload-arch=gfx90a -fdo-concurrent=device $f.f90 -o $f.x 2>/dev/null || exit 1
  echo "$f: $($RUN ./$f.x 2>&1 | grep -v 'Failed to load' | head -1)"
done
rm -f *.x
