#!/bin/bash
# Download and extract the AFAR compiler and the MOM6 dependency sources into $MOM_ROOT.
# Anything already extracted is skipped, so it is safe to re-run.
#   MOM_ROOT=/path/to/mom ./fetch_sources.sh      (default: four levels above this file)
set -euo pipefail
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOT="${MOM_ROOT:-$(cd "$here/../../../.." && pwd)}"
cd "$ROOT"

AFAR_NAME=therock-afar-24.4.0-multiarch-10.3.0-a71da8f
AFAR_URL=https://repo.radeon.com/rocm/misc/flang/$AFAR_NAME.tar.bz2

# fetch <dir that the tarball unpacks to> <url> <local tarball name>
fetch() {
  local dir=$1 url=$2 tb=$3
  if [[ -d $dir ]]; then echo "have   $ROOT/$dir"; return; fi
  if [[ ! -f $tb ]]; then
    echo "get    $url"
    curl -fL --retry 3 -o "$tb.part" "$url" && mv "$tb.part" "$tb"
  fi
  echo "unpack $tb"
  tar -xf "$tb"
  [[ -d $dir ]] || { echo "error: $tb did not unpack to $dir" >&2; exit 1; }
}

fetch "$AFAR_NAME"            "$AFAR_URL"                                                                   "$AFAR_NAME.tar.bz2"
fetch mpich-5.0.1             https://www.mpich.org/static/downloads/5.0.1/mpich-5.0.1.tar.gz               mpich-5.0.1.tar.gz
fetch hdf5-2.2.0              https://github.com/HDFGroup/hdf5/archive/refs/tags/2.2.0.tar.gz               hdf5-2.2.0.tar.gz
fetch netcdf-c-4.10.1         https://github.com/Unidata/netcdf-c/archive/refs/tags/v4.10.1.tar.gz          netcdf-c-4.10.1.tar.gz
fetch netcdf-fortran-4.6.4    https://github.com/Unidata/netcdf-fortran/archive/refs/tags/v4.6.4.tar.gz     netcdf-fortran-4.6.4.tar.gz
echo "sources ready in $ROOT"
