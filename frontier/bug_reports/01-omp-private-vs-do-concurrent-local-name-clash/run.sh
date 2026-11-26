#!/bin/bash
# Reproduce bug 01 with the AFAR 24.4.0 drop.
cd "$(dirname "$0")"; source ../../afar_env.sh
try() { echo "\$ $*"; "$@" -o /dev/null 2>&1 | grep -E -m3 'error|Segmentation|genPrivatizers' || echo "  (compiles)"; echo; }
# host only: -fopenmp is enough
try amdflang -c -fopenmp -fdo-concurrent=none mre_redefinition.f90
try amdflang -c -fopenmp -fdo-concurrent=host mre_redefinition.f90
try amdflang -c -fopenmp -fdo-concurrent=none mre_lookup_failure.f90
# no explicit private clause: implicitly private parallel-do index
try amdflang -c -fopenmp mre_implicit_loop_index.f90
# offload, as MOM6 builds it
try amdflang -c -O2 -fopenmp --offload-arch=gfx90a -fdo-concurrent=device mre_offload.f90
# control: same file without -fopenmp
try amdflang -c mre_redefinition.f90
# workaround
try amdflang -c -O2 -fopenmp --offload-arch=gfx90a -fdo-concurrent=device -mmlir --enable-delayed-privatization=false mre_offload.f90
