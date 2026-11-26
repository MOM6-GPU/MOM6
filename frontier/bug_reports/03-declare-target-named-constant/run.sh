#!/bin/bash
cd "$(dirname "$0")"; source ../../afar_env.sh
echo "\$ amdflang -c -fopenmp mre_dt_param.f90"; amdflang -c -fopenmp mre_dt_param.f90 -o /dev/null 2>&1 | grep -E 'error|warning'
