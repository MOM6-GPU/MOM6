#!/bin/bash
cd "$(dirname "$0")"; source ../../afar_env.sh
F="-c -O2 -fopenmp --offload-arch=gfx90a -fdo-concurrent=device"
echo "\$ amdflang -g $F mre_nested_reduction_debuginfo.f90"; amdflang -g $F mre_nested_reduction_debuginfo.f90 -o /dev/null 2>&1 | grep -E -m6 'error|conflicting|!DI|ptr' ; echo
echo "\$ amdflang $F mre_nested_reduction_debuginfo.f90   (no -g)"; amdflang $F mre_nested_reduction_debuginfo.f90 -o /dev/null 2>&1 | grep -E -m3 'error' || echo "  (compiles)"
