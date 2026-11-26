#!/bin/bash
# Run ocean_only/double_gyre with the AFAR GPU and CPU builds. Run it on a compute node (inside an
# allocation). Each run uses its own directory: ocean_only/runs_afar/double_gyre_{gpu,cpu}.
#   run_double_gyre.sh [gpu|cpu|both]   (default: both)
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$here/afar_env.sh"
oo="$(cd "$here/../../../ocean_only" && pwd)"
export OMP_NUM_THREADS=1
which=${1:-both}

run() {  # run <gpu|cpu> <build dir> <extra srun args>
  local d="$oo/runs_afar/double_gyre_$1" exe="$oo/$2/MOM6"
  mkdir -p "$d/RESTART"
  for f in input.nml MOM_input MOM_override diag_table; do
    [[ -e "$d/$f" ]] || cp "$oo/double_gyre/$f" "$d/"
  done
  cd "$d" && rm -f ocean.stats* && echo "=== $1: $exe" &&
  /usr/bin/time -f "$1 wall: %e s" srun -n1 -c1 $3 "$exe" > run.log 2>&1
  echo "exit=$?"; tail -3 run.log; echo "--- ocean.stats"; tail -n +3 ocean.stats 2>/dev/null | head -12
}
[[ $which == cpu || $which == both ]] && run cpu build_cpu ""
[[ $which == gpu || $which == both ]] && run gpu build "--gpus=1"
