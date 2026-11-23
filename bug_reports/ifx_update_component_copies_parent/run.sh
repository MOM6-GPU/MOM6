#!/bin/bash
# Part 1 runs anywhere: prints the OpenMP map-type table that ifx emits for the update.
# Part 2 needs an Aurora GPU compute node.
cd "$(dirname "$0")"
mkdir -p build && cd build
F="-O2 -qopenmp -fopenmp-targets=spir64"
ifx --version | head -1

maptypes() {  # print the map-type table used by update_from in the host assembly
  local s=$1
  local lab=$(awk '/^repro_mod_mp_update_from_:/{f=1} f && /offload_maptypes/{match($0,/\.L\.offload_maptypes[.0-9]*/); print substr($0,RSTART,RLENGTH); exit}' "$s")
  awk -v l="$lab:" '$0==l{f=1;next} f&&/\.quad/{printf "0x%x ", $2; next} f{exit}' "$s"; echo
}

for v in bug workaround; do
  D=""; [ $v = workaround ] && D=-DWORKAROUND
  echo "=== $v ($D)"
  ifx $F $D -S ../reproducer.F90 -o $v.s > $v.log 2>&1 || { echo "compile FAILED"; continue; }
  echo "map types for update_from: $(maptypes $v.s)  (0x2 = from; bug: 2 entries, fixed: 1)"
  ifx $F $D ../reproducer.F90 -o $v.x >> $v.log 2>&1 && ./$v.x 2>&1 | grep -m3 "CS%\|PASS\|FAIL\|No images"
done
