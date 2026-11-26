#!/bin/bash
# Bug 02: compile the same valid file several times; flang crashes in some runs, at random.
cd "$(dirname "$(readlink -f "$0")")"; source ../../afar_env.sh
[[ -f mre_parallel_warning_print.f90 ]] || python3 -I gen_mre.py 40 64
F="-c -O2 -fopenmp --offload-arch=gfx90a"
for t in 1 2 3 4 5 6 7 8; do
  printf "run %d: " $t
  amdflang $F mre_parallel_warning_print.f90 -o /dev/null 2>&1 \
    | grep -m1 -oE 'double free[^\n]*|corrupted[^\n]*|Segmentation fault|malloc\(\)[^\n]*|free\(\)[^\n]*' || echo "no crash"
done
printf "with -mmlir --mlir-disable-threading (x4): "
for t in 1 2 3 4; do amdflang $F -mmlir --mlir-disable-threading mre_parallel_warning_print.f90 -o /dev/null 2>&1 \
  | grep -m1 -qE 'double free|corrupted|Segmentation' && printf "CRASH " || printf "ok "; done; echo
