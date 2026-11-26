#!/bin/bash
cd "$(dirname "$0")"; source ../../afar_env.sh
amdflang -c -fopenmp mre_teams_loop_array_reduction.f90 -o /dev/null
