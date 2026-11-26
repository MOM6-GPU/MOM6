#!/bin/bash
# Needs a GPU. On a compute node run directly; from a login node set RUN="srun --jobid=<id> --overlap -n1 --gpus=1".
cd "$(dirname "$0")"
source ../../afar_env.sh
RUN=${RUN:-}
FL="-fopenmp --offload-arch=gfx90a -fdo-concurrent=device"
for f in mre_target_region mre_teams_loop; do
  for o in -O2 -O0; do
    amdflang $o $FL $f.f90 -o $f$o || exit 1
    echo "== $f $o: $($RUN ./$f$o 2>&1 | grep -v 'Failed to load' | head -2 | tr '\n' ' ')"
  done
done
amdflang -O2 $FL mre_teams_loop.f90 -o mre_teams_loop_fb
echo "== mre_teams_loop -O2, OMP_TARGET_OFFLOAD=DISABLED: $(OMP_TARGET_OFFLOAD=DISABLED $RUN ./mre_teams_loop_fb 2>&1 | head -1)"
echo "== IR after omp-do-concurrent-conversion (nested omp.target):"
amdflang -fc1 -fopenmp -fdo-concurrent=device -emit-hlfir \
  -mmlir --mlir-print-ir-after=omp-do-concurrent-conversion mre_target_region.f90 -o /dev/null 2>&1 \
  | grep -E "^ *omp\.target" | cut -c1-60
rm -f mre_target_region-O* mre_teams_loop-O* mre_teams_loop_fb
