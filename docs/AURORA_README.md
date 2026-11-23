# MOM6 GPU port on Aurora (ifx + OpenMP offload)

How to build and run the MOM6 GPU port on ALCF Aurora with Intel `ifx`, and what to watch out
for. The work is on branch `fix/aurora`, based on `dev/gpu` from
[MOM6-GPU/MOM6](https://github.com/MOM6-GPU/MOM6) (remote `gpu`; last rebased onto
`c914fa41f`, 2026-10-31). The current status and history are in
[`SUMMARY.md`](../SUMMARY.md); compiler bugs and their minimal reproducers are in
[`bug_reports/`](../bug_reports/README.md).

Tested with `ifx (IFX) 2026.1.0 20260617` on Intel Data Center GPU Max (PVC), using the
`ocean_only/double_gyre` case.

## Layout

This assumes the MOM6-examples directory layout:

```
<root>/
  ocean_only/          build and run directory (Makefile, config.mk, env.sh, experiments)
    build/             MOM6 build (autoconf), binary: build/MOM6
    double_gyre/       test case
    jobs/              PBS job scripts and their output (see "Running")
  shared/fms/build/    FMS library build (libFMS.a), built automatically
  src/MOM6/            this repository
  src/FMS2/            FMS source
```

## Environment

Load the modules from `ocean_only/env.sh` in every shell that builds or runs:

```bash
cd <root>/ocean_only
source env.sh          # module load netcdf-c netcdf-fortran python
```

`python` matters: the system `python3` is 3.6, which is too old for some helper scripts.

## Building

All settings are in `ocean_only/config.mk`:

```make
CC = icx
MPICC = mpicc
FC = ifx
MPIFC = mpifort
PYTHON = python3
FCFLAGS = -g -O3 -qopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent -DIFX_WORKAROUNDS_MOM6 -DMOM_OPENMP_GPU
FMS_FCFLAGS = -g -O3 -qopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent
LDFLAGS = -qopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent
```

- `-fopenmp-targets=spir64` builds device code for Intel GPUs. The device code is compiled
  to native code when the program loads (JIT).
- `-fopenmp-target-do-concurrent` offloads `do concurrent` loops as well as `!$omp target`
  regions.
- `-DIFX_WORKAROUNDS_MOM6` turns on the source workarounds for ifx bugs (see below). **It is
  required**: without it, several files hit internal compiler errors.
- `-DMOM_OPENMP_GPU` selects the GPU code paths that nvfortran gets from
  `__NVCOMPILER_OPENMP_GPU`, mainly whole-domain block-size defaults. **Without it the run is
  about 5x slower**: the block defaults fall back to one row per kernel launch, so the
  10-day double_gyre run takes 1390 s instead of 262 s. Answers are bitwise identical either
  way. The nvhpc-only `bind(parallel,teams)` clause in `MOM_ALE.F90` stays nvfortran-only.
- The OpenMP flags must also be in `LDFLAGS`. `libFMS.a` and the MOM6 objects need the
  offload runtime and device linker.

Build from the login node:

```bash
cd <root>/ocean_only
source env.sh
make -j
```

This builds FMS into `shared/fms/build` if needed, configures MOM6 into `ocean_only/build`,
and links `build/MOM6`.

**After changing `FCFLAGS`,** reconfigure. `FCFLAGS` is fixed when `configure` runs, so
`make` alone does not pick up the change:

```bash
rm -f build/config.cache build/config.status build/Makefile
make -j
```

### `IFX_WORKAROUNDS_MOM6`

Every ifx-specific change in the source looks like this:

```fortran
#ifdef IFX_WORKAROUNDS_MOM6
  ! Avoid an ifx ..., see bug_reports/<report_dir>
  <workaround>
#else
  <original code>
#endif
```

- **Without the macro, the code is unchanged.** Other compilers (e.g. nvfortran) are not
  affected.
- **Answers are meant to stay bitwise identical.** Exceptions are noted in the reports.
- **To see where a workaround applies,** grep for its report directory name:
  `grep -rn ifx_dc_dtype_bounds_ice src`.
- **Dependency scanning:** `ac/makedep` doesn't see this macro (it only gets configure's
  `DEFS`), so workarounds must not change module dependencies.

## Running

There are no GPUs on the login nodes. Run on compute nodes, interactively or in batch.

### Interactive

```bash
qsub -l select=1 -l walltime=30:00 -l filesystems=flare -A <project> -q debug -I
# on the compute node:
cd <root>/ocean_only && source env.sh
cd double_gyre
mpirun -np 1 ../build/MOM6
```

### Batch

Job scripts must live on a filesystem the compute nodes can see (home or flare), not in
`/tmp`. Example (`ocean_only/jobs/dg.pbs`):

```bash
#!/bin/bash
#PBS -N mom6_dg
#PBS -l select=1
#PBS -l walltime=00:15:00
#PBS -l filesystems=flare
#PBS -A <project>
#PBS -q debug
#PBS -j oe
#PBS -o <root>/ocean_only/jobs/dg.out

source <root>/ocean_only/env.sh >/dev/null 2>&1
cd <root>/ocean_only/double_gyre
mpirun -np 1 ../build/MOM6 > <root>/ocean_only/jobs/dg.model.log 2>&1
echo "MOM6 exit status: $?"
```

Submit with `qsub dg.pbs`, and watch progress with `qstat -u $USER` and
`tail -f double_gyre/ocean.stats`.

- **Run length:** double_gyre runs 10 model days (`DAYMAX = 10`, `DT = 1200`, so 720
  steps; `ocean.stats` gets one line per day).
- **Recommended runtime setting:** `export LIBOMPTARGET_LEVEL_ZERO_STAGING_BUFFER_SIZE=0`
  (see caveat 1). All validated runs used it.
- **Expected answers** (CPU reference, which the GPU matches to about 12 significant
  digits):

  | Day | Energy | Max CFL |
  |---|---|---|
  | 0 | 1.4237e-13 | 0 |
  | 1 | 4.5804e-06 | 0.00023 |
  | 10 | 4.6047e-05 | 0.00100 |

  - The mass error stays at round-off (≲ 1e-14).
  - **An energy around 1e-3 at day 1, or above 1 by day 10, means wrong answers.** Earlier
    builds of this port did that while looking smooth and healthy (see caveat 3, bugs 9–11).
- **Checking against a CPU build:** see "Verifying against a CPU build" below.
- **Speed:** about 2.3 minutes of walltime per model day on one GPU with
  `STAGING_BUFFER_SIZE=0`, so day 10 takes about 23 minutes. A CPU build does all 10 days in
  under a minute. On this small (44×40) grid the GPU time is almost all kernel-launch and
  data-mapping overhead, not compute.

### Verifying against a CPU build

A GPU run that completes can still be wrong, so compare it with a CPU build of the same
source.

1. **Build FMS and MOM6 for the CPU** in separate directories: `shared/fms/build_cpu` and
   `ocean_only/build_cpu`.
   - Configure with `-g -O2` and no OpenMP; configure adds `-r8 -fprotect-parens`.
   - Build with `make -C build_cpu`. Don't override `FCFLAGS` on the command line: that
     drops `-r8`.
2. **Compare `ocean.stats` day by day.** Expect about 12 matching digits while the GPU build
   uses `-O3` with ifx's default FP model. Bitwise agreement needs strict FP on both builds.
3. **To find where a difference starts,** run one step (`#override DAYMAX = 0.0139`) with
   `#override DEBUG = True` on both builds.
   - Line up the checksum lines (`mean= min= max=` ... label) in order, and look for the
     first that differs by more than roundoff relative to the field's magnitude.
   - Then rerun the GPU binary with `OMP_TARGET_OFFLOAD=DISABLED`. If that also differs
     from the CPU build, the problem isn't GPU-specific (bug 11 was found this way).

## Caveats

### 1. Staging-buffer overrun in the Intel offload runtime

**Symptom without the workaround:** the model stops in the first timestep with

```
FATAL: btstep: number of barotropic step (nstep+nfilter) is 0
```

**Cause:** an Intel Level Zero runtime bug. A single `!$omp target update to(CS)` on a
structure with allocatable components, inside a mapped parent, expands into one large
transfer followed by thousands of small staged transfers. Some of the small ones then
deliver the data of a transfer submitted 64 places later. In `barotropic_init`, the scalars
of `CS` arrived as garbage (-5.8e+303), so the barotropic time step came out at about 1e19 s.
Reproducer and details: `bug_reports/ifx_l0_staging_buffer_overrun`.

**Fixed in the source:** under `IFX_WORKAROUNDS_MOM6`, `barotropic_init` updates `CS` through a
byte view of its storage, a single map entry. No runtime setting is needed for double_gyre.

**Fallbacks, if another site shows the same symptom** (garbage scalars or wrong values right
after a `target update`):

| Setting | Notes |
|---|---|
| `export LIBOMPTARGET_LEVEL_ZERO_STAGING_BUFFER_SIZE=0` | Fixes every variant of the reproducer. Not yet tested on a full MOM6 run. |
| `export LIBOMPTARGET_LEVEL_ZERO_COMMAND_MODE=sync` | Known to work for double_gyre, but serializes every copy and kernel (about 2× slower). |

Eight other whole-structure `target update to(...)` directives in MOM6 have the same shape:
`initialize_MOM` (two), the pressure-force init, `MOM_lateral_mixing_coeffs`, `vertvisc_init`
and others. They haven't failed in double_gyre, but other configurations could hit them.

**Debug logging hides it:** `LIBOMPTARGET_DEBUG=1` slows the host down enough that the bug
doesn't occur, so debug-log runs can look fine when normal runs fail.

### 2. Debugging tools can change the behavior

- **`LIBOMPTARGET_DEBUG=1`:** hides the bug in caveat 1, and writes about 2 GB of log per
  short run. Still very useful: the last `__omp_offloading_..._l<line>` kernel before a
  GPU fault names the routine and source line, and the `Moving N bytes (tgt:...) ->
  (hst:...)` lines show unexpected copies.
- **`-O0`:** some bugs (e.g. `bug_reports/ifx_dc_reduce_locality`) only appear at `-O3`.

### 3. Known ifx problems that need source workarounds

All are handled under `IFX_WORKAROUNDS_MOM6`, with a reproducer in `bug_reports/`.

| Report | Symptom |
|---|---|
| `ifx_dc_dtype_bounds_ice` | ICE when `do concurrent` bounds come from 2+ components of one derived-type object |
| `ifx_map_extended_type_array_ice` | ICE when mapping an array of an extended type with an allocatable component |
| `ifx_declare_target_separate_module_procedure` | `declare target` separate module procedures: either error #8682 or no device code |
| `ifx_kernel_args_explicit_shape_bounds` | kernels over the 2 KiB argument limit, because explicit-shape arrays cost 40 B each |
| `ifx_update_component_copies_parent` | `target update to/from(X%comp)` with a pointer/allocatable `X` transfers all of `X` |
| `ifx_dc_reduce_locality` | conditional min reduction wrong at `-O3` (fast-math overflow of the `huge()` identity) |
| `ifx_l0_staging_buffer_overrun` | caveat 1 |
| `ifx_map_noncontiguous_section` | **Silent wrong data:** a device loop over a non-contiguous dummy array (`a(isc:iec,jsc:jec)`) reads zeros in its trailing columns. Broke every `reproducing_sum`. |
| `ifx_dt_component_write_lost` | **Silent wrong data:** components allocated and mapped after their parent object was sent to the device keep stale descriptors. Writes are lost and reads come from the wrong memory. Broke the bottom drag, the baroclinic acceleration and the barotropic transport. |
| `ifx_associate_write_lost` | **Silent wrong data:** writes to an `associate` name inside an offloaded `do concurrent` are lost, even with offload disabled. Broke the sea-level average and the tracer-transport reset. |
| `ifx_dc_array_reduction` | ICE for `do concurrent` with an array `reduce(+)` plus `reduce(max)` (no MOM6 code has this shape) |

### 4. Patterns to avoid in new GPU code

- **Pointer components of a mapped structure aren't mapped with it.** Allocatable
  components are, but a kernel reading `CS%ptr(i,j)` gets an unattached pointer (GPU read
  at 0x0) unless the target is mapped explicitly, e.g. `!$omp target data map(to: CS%Hml)`.
- **Referencing `CS%...` in a kernel when `CS` isn't on the device** maps the whole
  structure `tofrom` on every call. That's slow, and copying it back can corrupt host
  pointers. Use `associate` names for the arrays, or keep the structure mapped.
- **Never assign to an `associate` name inside a `do concurrent`:** ifx drops the writes
  (`bug_reports/ifx_associate_write_lost`). Reading is fine. To write, use an explicit
  `!$omp target teams loop`, a pointer, or a dummy argument.
  `ocean_only/jobs/tools/assoc_dc_writes.py` lists offending loops.
- **If a structure is sent to the device before its arrays are allocated** (`map(alloc: CS)`
  or `target update to(CS)` early in an init routine), send it again with
  `!$omp target update to(CS)` after its last array has been allocated and mapped
  (`bug_reports/ifx_dt_component_write_lost`).
- **Don't run device loops over non-contiguous array sections passed as dummy arguments.**
  Copy them to a contiguous temporary first (`bug_reports/ifx_map_noncontiguous_section`).
- **Optional arguments inside target regions:** ifx warns with #5590 ("Optional parameters
  will fault if not present"). Copy them into local variables or pointers before the
  region.
- **`!$omp loop` inside a plain `!$omp target` (no `teams`/`parallel`) runs on one GPU
  thread.** This made `zonal/meridional_flux_adjust` take minutes per call; they're now
  separate `target teams loop` kernels under the macro.
- **Procedures called from offloaded loops need `!$omp declare target`.** Otherwise ifx
  silently leaves the loop on the host (warning #5476 "will not be offloaded"), which is
  slow and can give wrong answers against device-resident data.
- **Whole-structure `!$omp target update to(CS)`** on a structure with allocatable components
  (especially inside a mapped parent) can expand into thousands of small transfers and
  trigger the runtime bug in caveat 1. Prefer updating the specific arrays, or the
  byte-view update used in `barotropic_init`, when no components are mapped yet.
- **Many explicit-shape arrays in one kernel** can exceed the 2 KiB kernel-argument limit.
  The failure only shows when the program starts on the GPU. Use allocatable work arrays,
  or check with an AOT link (below).

### 5. Code paths known to be unsafe but not exercised by double_gyre

- Structures that may still have the stale-descriptor problem (bug 10) in features
  double_gyre doesn't use: `thickness_diffuse_CS` (GME and slope diagnostics),
  `set_visc_CS`, and the tracer packages.
- `horizontal_viscosity` called without `OBC` (the unsplit solvers), and
  `calc_isoneutral_slopes` called without `OBC` (ML-MEKE features, `meso_sfn_ANN`): these
  touch an absent optional argument inside a target region.
- 20 allocatable `CS` components are used in kernels without explicit maps. This is low
  risk, but unverified.

## Debugging tips

- **GPU fault ("Segmentation fault from GPU at 0x0"):** rerun with
  `LIBOMPTARGET_DEBUG=1 ... > log 2>&1`, then
  `grep -n __omp_offloading log | tail` gives the last kernel launched and its source line.
- **Host crash:** `gdb ../build/MOM6 core.<host>.<pid>` then `bt`. Use `gdb-oneapi`
  (`/opt/aurora/<version>/oneapi/debugger/latest/opt/debugger/bin/gdb-oneapi`) to print
  Fortran derived types; the system gdb crashes on them.
- **"Module link failed" or "kernel arguments exceeds limit" when the program starts:**
  inspect the device code without a GPU:
  ```bash
  T=/opt/aurora/<version>/oneapi/compiler/<ver>/bin/compiler
  $T/clang-offload-bundler -type=o -targets=openmp-spir64 -input=X.o -output=X.dev -unbundle
  $T/llvm-spirv -spirv-ext=+all -spirv-text X.dev -o X.spt
  ```
  - Kernel names carry the source line (`..._l550`).
  - `FunctionParameter` entries give the argument list.
  - `LinkageAttributes ... Import` vs `Export` across objects shows unresolved device
    symbols.
- **Check every kernel against the 2 KiB argument limit without a GPU:** link ahead of
  time for PVC:
  ```bash
  mpifort -qopenmp -fopenmp-targets=spir64_gen -Xopenmp-target-backend "-device pvc" \
    -fopenmp-target-do-concurrent -o MOM6_aot.x build/*.o -L<fms build> -lFMS -lnetcdff -lnetcdf
  ```
- **What data transfers a directive generates:** compile with `-S` and read the
  `.L.offload_maptypes*` tables (`0x1` to, `0x2` from, `0x20` kernel argument, `0x200`
  implicit).
