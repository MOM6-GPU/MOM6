# MOM6 (dev/gpu) on Frontier with the AMD AFAR flang

How to build and run MOM6 + FMS with OpenMP offload to MI250X (gfx90a) using AMD's AFAR
flang drop, and the compiler bugs found doing it (`bug_reports/`).

| | |
|---|---|
| Compiler | AMD AFAR drop 24.4.0 (TheRock ROCm 10.3.0), AMD flang 24.0.0git, ROCm/llvm-project `af5d6a9790939cc301486abeec5a51ee48f59c18` |
| Download | <https://repo.radeon.com/rocm/misc/flang/therock-afar-24.4.0-multiarch-10.3.0-a71da8f.tar.bz2> |
| Machine | Frontier, MI250X (`gfx90a`) |
| MOM6 | `dev/gpu` (this branch: `fix/frontier`) |
| Status | double_gyre runs 10 days on one GCD, matches the CPU build to roundoff |

The AFAR drop is self-contained (its own HSA/HIP runtime): **do not** `module load rocm`.
Everything uses AFAR only, including MPI, HDF5 and netCDF, because flang rejects `.mod`
files built by any other flang version.

## Layout
All paths hang off `MOM_ROOT`, the directory that holds `MOM6-examples`:
```
$MOM_ROOT/
  therock-afar-24.4.0-multiarch-10.3.0-a71da8f/   AFAR (fetch_sources.sh)
  mpich-5.0.1/ hdf5-2.2.0/ netcdf-c-4.10.1/ netcdf-fortran-4.6.4/   dependency sources
  install_mom_deps_afar/                          MPICH + HDF5 + netCDF built with AFAR
  MOM6-examples/
    ocean_only/                                   builds: build/ (GPU), build_cpu/ (CPU)
    shared/fms/                                   builds: build/ (GPU), build_cpu/ (CPU)
    src/FMS2/
    src/MOM6/frontier/                            this directory
```

## Files
| File | Purpose |
|---|---|
| `afar_env.sh` | `source` it before building or running: sets `MOM_ROOT`, `AFAR`, `MOM_DEPS`, `ROCM_PATH`, `PATH`, `LD_LIBRARY_PATH` |
| `fetch_sources.sh` | downloads and unpacks AFAR and the dependency sources into `$MOM_ROOT` (skips what is there) |
| `build_mom_deps.sh` | builds MPICH, HDF5, netCDF-C, netCDF-Fortran with AFAR into `install_mom_deps_afar` |
| `afar.config.mk` | `ocean_only/config.mk` for the GPU build |
| `afar_workarounds.mk` | per-file compiler workaround flags plus `-DAMD_WORKAROUNDS`; passed as an extra makefile |
| `patches/fms-mpp_chksum_int.patch` | FMS fix needed with this compiler |
| `run_double_gyre.sh` | runs double_gyre with the GPU and/or CPU build |
| `bug_reports/` | one directory per compiler bug: README, MRE, `run.sh` |

## Build
Run the heavy steps on a compute node (e.g. inside `salloc`), not on a login node.

```bash
cd $MOM_ROOT/MOM6-examples/src/MOM6/frontier
./fetch_sources.sh                 # AFAR + dependency sources
source afar_env.sh
./build_mom_deps.sh                # MPICH, HDF5, netCDF -> $MOM_ROOT/install_mom_deps_afar

cd $MOM_ROOT/MOM6-examples
git -C src/FMS2 apply ../MOM6/frontier/patches/fms-mpp_chksum_int.patch
```

**GPU build** (`ocean_only/build/MOM6`). The first `make` builds FMS (`shared/fms/build`) and
configures MOM6; the second compiles MOM6 with the workarounds:
```bash
cd $MOM_ROOT/MOM6-examples/ocean_only
cp ../src/MOM6/frontier/afar.config.mk config.mk
make build/config.status
make -C build -j32 -f Makefile -f ../../src/MOM6/frontier/afar_workarounds.mk MOM6
```
Flags: `-g -O2 -fopenmp --offload-arch=gfx90a -fdo-concurrent=device -D__NVCOMPILER_OPENMP_GPU`
(FMS: `-g -O2 -fopenmp --offload-arch=gfx90a`). `__NVCOMPILER_OPENMP_GPU` is predefined by
nvfortran but not flang; dev/gpu uses it to select its GPU code paths (whole-domain blocks, no
per-`k` early exits), and without it the GPU build is very slow.

**CPU build** (`ocean_only/build_cpu/MOM6`), serial, no OpenMP, as a reference:
```bash
make BUILD=build_cpu FMS_BUILD=../shared/fms/build_cpu FCFLAGS="-g -O2" FMS_FCFLAGS="-g -O2" \
     build_cpu/config.status
make -C build_cpu -j32 MOM6
```
Compile MOM6 itself with a plain `make -C build_cpu`: passing `FCFLAGS` on the command line of
that step would replace the `-fdefault-real-8 -fdefault-double-8` that configure adds.

## Run
```bash
$MOM_ROOT/MOM6-examples/src/MOM6/frontier/run_double_gyre.sh gpu    # or cpu, or both (default)
```
Runs in `ocean_only/runs_afar/double_gyre_{gpu,cpu}/` with `srun -n1` (`--gpus=1` for GPU), so
it must be run inside an allocation. Lines like `omptarget error: Failed to load symbol _QM...`
at start-up are harmless. Expected `ocean.stats`:
```
Day 1:  En 4.5804317887743E-06   Mass 5.28818E+18
Day 5:  En 1.8260222693482E-05   Mass 5.28818E+18
```
GPU and CPU agree to roundoff, not bitwise.

## Workarounds
Compiler bugs are worked around in two ways, both pointing at `bug_reports/NN-*`:
- **Flags** in `afar_workarounds.mk`: per-file `-mmlir --enable-delayed-privatization=false`
  (01), `-g0` (04), and `-mmlir --mlir-disable-threading` for all files (02).
- **Source changes** guarded by `AMD_WORKAROUNDS`, with the original code in the `#else`
  branch, so the dev/gpu code is unchanged when the macro is not defined:
  ```bash
  grep -rn AMD_WORKAROUNDS src      # from src/MOM6
  ```

Some changes on this branch fix MOM6 itself, not the compiler, and are not guarded:
`ac/configure.ac` (`jmp_buf` size probe), `MOM_barotropic.F90` (stray `!$omp do` inside
`do concurrent`), `MOM.F90` (`CS%Hml` mapped to the device).

## Known problems
- **Slow:** double_gyre takes ~21 min on the GPU vs ~8 s on the CPU. Not investigated yet.
- **Bug 05 is not worked around:** 50 `do concurrent` loops nested inside `!$omp target`
  regions are silently skipped on the GPU (`MOM_tracer_advect.F90`, `MOM.F90`
  `extract_surface_state`, `MOM_diabatic_aux.F90`, `MOM_isopycnal_slopes.F90`). double_gyre
  doesn't depend on them; configurations with tracers or T/S will give wrong answers.

See `bug_reports/README.md` for the full list of compiler bugs.
