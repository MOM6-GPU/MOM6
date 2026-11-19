# MOM6 on Aurora with ifx: compiler bugs and workarounds

Work from 2026-11-18 on getting the MOM6 GPU port (`dev/gpu`) to build and run on
Aurora with `ifx (IFX) 2026.1.0 20260617`, offloading with
`-qopenmp -fopenmp-targets=spir64 -fopenmp-target-do-concurrent`. The test case is
`ocean_only/double_gyre`.

Goal: find the root cause of each failure, report compiler bugs to Intel with minimal
runnable reproducers (MREs), and work around them in MOM6 without changing answers. This
replaces the trial-and-error fixes in `~/MOM6-examples/src/MOM6`.

## Status

- **Build:** compiles and links (`make -j` in `ocean_only`).
- **Run:** double_gyre **runs to day 10** (720 steps, exit status 0) in the default async
  runtime mode, with no special settings. That's job 9103608: 12 min 26 s, about 1.2 min
  per model day.
  - **Diagnostics:** energy spins up smoothly (about 14.5 at day 10), max CFL 0.129, no
    truncations, mass error about 1e-14.
- **The two fixes that got it running:**
  - **Bug 8, a staging-buffer overrun in Intel's Level Zero runtime.** `barotropic_init`'s
    `!$omp target update to(CS)` expands into one large transfer plus 52,163 small staged
    ones, and some of those deliver the data of the transfer 64 places later. `CS`'s
    scalars arrived as garbage, which caused `nstep = 0`. Fixed under the macro by
    updating `CS` through a byte view of its storage.
  - **`zonal/meridional_flux_adjust` ran their whole convergence iteration on one GPU
    thread** (`!$omp loop` inside a plain `!$omp target`). Restructured under the macro
    into a host iteration loop with one `target teams loop` per inner loop.
- **Compiler/runtime issues:** 8 bugs with reproducers in `bug_reports/`, plus 3
  "not reproduced" investigations.
- **MOM6 port bugs fixed:** 4 (not ifx-specific, no macro).
- **Docs:** `docs/AURORA_README.md` covers how to build and run on Aurora, and the caveats.
- **GPU testing:** batch jobs work. See "Batch jobs".

## GPU runs so far

| Run | Failure | Cause | Fix |
|---|---|---|---|
| 1 | Level Zero "kernel arguments exceeds limit" (2176 > 2048 B) | Bug 4 | `set_viscous_BBL` work arrays made allocatable |
| 2 | "Module link failed" | Bug 3: `exp_repro` had no device code (my first workaround was wrong) | Directive moved to the body |
| 3 | GPU read at 0x0 in `extract_surface_state__l4510` | Port bug: `CS%Hml` pointer never mapped | `target data map(to: CS%Hml)` |
| 4 | Host SIGSEGV in `get_zlike_CS` after `step_mom__l819` | Port bug: kernels implicitly mapped all 113 KB of `CS` `tofrom`, corrupting host pointers | 5 loops use `associate` names |
| 5 | `btcalc: Module MOM_barotropic must be initialized` | Bug 5: `update from(CS%diffu)` copied all 557 KB of `CS` | 49 updates use `associate` |
| 6 | Host SIGSEGV in `zonal_flux_adjust` | Absent optional `OBC` in a target region (bug 6, unconfirmed) | Local `OBC_loc` pointer |
| 7 | `btstep: ... (nstep+nfilter) is 0` | Thought to be bug 7 (conditional min reduction) | Reduce the max instead: **didn't help** |
| 8 | Same | Thought to be optional scalars made PRIVATE | Local copies: **didn't help**; their MRE passes |
| 9–13 | Same | Debug runs: `max_Idt2 = 0` because `CS%bebt` reads as garbage on the GPU | – |
| 14 | Same, only without `LIBOMPTARGET_DEBUG` | Bug 8 (first thought to be a kernel race) | `COMMAND_MODE=sync` (temporary) |
| 15 | `sync`: stuck after the first step | `flux_adjust` iteration serialized on one GPU thread | Restructured as `target teams loop` kernels |
| 16 | Runs with `sync`: day 9 of 10 in 15 minutes, about 2.5 min/day | – | – |
| 17 | **Default async mode: day 10, exit 0, about 1.2 min/day** (job 9103608) | Bug 8 is a staging-buffer overrun | `barotropic_init` updates `CS` through a byte view |

**Bugs 1 and 2 were compile-time ICEs,** found and fixed before the first run.

**How each run was diagnosed:**
- **GPU faults:** the last `__omp_offloading_..._l<line>` kernel in a
  `LIBOMPTARGET_DEBUG=1` log.
- **Host crashes:** `gdb` on the core file.
- **Corrupted host data:** large `Moving N bytes (tgt:...) -> (hst:...)` copies in the
  same log, with the `Name=` of each map entry.

## The `IFX_WORKAROUNDS_MOM6` macro

```fortran
#ifdef IFX_WORKAROUNDS_MOM6
  ! Avoid an ifx ..., see bug_reports/<report_dir>
  <workaround>
#else
  <original code>
#endif
```

- **Without the macro the code is unchanged.** All workarounds are bitwise identical,
  except bug 7's, whose reduction order was unspecified to begin with.
- **To find the sites,** grep for a report's directory name.
- **To turn it on,** `-DIFX_WORKAROUNDS_MOM6` is in `ocean_only/config.mk` `FCFLAGS`.
  That file is outside the repo.
- **After changing `FCFLAGS`,** delete `build/config.cache`, `build/config.status` and
  `build/Makefile`, then rerun `make`. `FCFLAGS` is fixed at configure time.
- **`ac/makedep` only sees configure's `$(DEFS)`, not `FCFLAGS`,** so workarounds must
  not change module dependencies.

## Compiler bugs (`bug_reports/`)

Each directory has a `README.md` (trigger, what does and doesn't trigger it, impact on
MOM6, workaround), a runnable `reproducer.F90` (a `program` with a `-DWORKAROUND` variant)
and `run.sh`. `bug_reports/README.md` is the index.

| # | Report | Kind | Status |
|---|---|---|---|
| 1 | `ifx_dc_dtype_bounds_ice` | ICE #5633 | Confirmed (compile) |
| 2 | `ifx_map_extended_type_array_ice` | ICE #5623, host too | Confirmed (compile) |
| 3 | `ifx_declare_target_separate_module_procedure` | #8682, or body never compiled for the device | Confirmed (device code); check the OpenMP wording before filing |
| 4 | `ifx_kernel_args_explicit_shape_bounds` | Kernel arguments over 2 KiB | Confirmed (AOT link) |
| 5 | `ifx_update_component_copies_parent` | Wrong data transfer | Confirmed (map tables + GPU run) |
| 6 | `ifx_absent_optional_in_target_region` | Host SIGSEGV | **Not reproduced:** the MRE passes on the GPU |
| 7 | `ifx_dc_reduce_locality` | Wrong reduction result at `-O3` | Confirmed (GPU run); `-fp-model precise` fixes it |
| 8 | `ifx_l0_staging_buffer_overrun` | Runtime: wrong data after a `target update` with many small transfers | Confirmed (GPU run, 19/20 wrong); minimal reproducer of about 130 lines |
| – | `ifx_implicit_map_struct_pointer_components` | Investigation notes | **Not reproduced:** the MRE passes on the GPU |
| – | `ifx_optional_scalar_private` | Investigation notes | **Not reproduced:** the MRE passes on the GPU |

### 1. ICE when `do concurrent` bounds come from one derived-type object

- **Trigger:** `do concurrent (j=G%jsd:G%jed, i=G%isd:G%ied)` (2 or more ranges using
  components of the same object) crashes the device compile.
- **Not triggered by:** one range, two different objects, local variables, or
  `!$omp target teams loop`.
- **Workaround:** bind the bounds with `associate`. 34 loops in 11 files.
- **Note:** the old comment in `config.mk` blamed "automatic arrays"; that was wrong.

### 2. ICE when mapping an array of an extended type

- **Trigger:** any OpenMP map of an array of a type that extends another and adds an
  allocatable component. This also fails without `-fopenmp-targets`.
- **Impact on MOM6:** `MOM_control_struct` contains this four levels deep
  (`CS%diag%remap_axes*(:)%piecemeal_3d%buffer(:)`), so any map of `CS` failed.
- **How it was found:** delta debugging (140 → 1 component, three levels down).
- **Workaround:** `buffer_2d` and `buffer_3d` in `MOM_diag_buffers.F90` don't extend the
  empty, never-polymorphic `buffer_base`.
- **Note:** the other tree's "size/complexity limit" note was wrong.

### 3. `declare target` on a separate module procedure

No placement works for every caller:

- **Interface and body** (the conforming form): error #8682.
- **Interface only:** the submodule body is never compiled for the device, so the GPU
  image fails to load ("Module link failed").
- **Body only:** works from `!$omp target` regions, but a `do concurrent` caller isn't
  offloaded (#5476).

**Workaround:** body only, for `exp_repro`. Its two device call sites are in
`!$omp target teams` regions.

### 4. Explicit-shape arrays overflow the 2 KiB kernel-argument limit

- **Cause:** each explicit-shape array costs a pointer plus 4 bounds values (40 B), even
  when all arrays share their bounds. An allocatable array costs 8 B.
- **When it shows:** JIT builds only fail when the image loads on the GPU.
- **Workaround:** 28 work arrays in `set_viscous_BBL` made allocatable. The kernels drop
  from 2176 B to 936 B and from 2112 B to 896 B.

### 5. `target update` of a component transfers the whole parent

- **Trigger:** with a pointer or allocatable base `CS`, `update from(CS%x)` also copies
  all of `CS` (map types `0x2 0x2` instead of `0x2`), and `update to` does the same in
  the other direction.
- **Impact on MOM6:** this overwrote `MOM_dyn_split_RK2_CS` with an uninitialized
  device copy.
- **Workaround:** bind the components with `associate`. 49 directives in 3 files.

### 6. Absent optional argument in a target region (unconfirmed)

- **What happened:** ifx warns #5590 ("will fault if not present"). MOM6 crashed in
  `zonal_flux_adjust` when called without `OBC`, and using a local pointer fixed it.
- **But:** the simple MRE passes on the GPU, and the core showed a jump to a garbage
  address, so the real trigger is narrower.
- **Do not file yet.**

### 7. Conditional min reduction returns its initial value at `-O3`

- **Trigger:** `if (v*r > 1) r = 1/v` with `reduce(min:r)` (or
  `omp ... reduction(min:r)`) returns the initial `r` at `-O3`. It's correct at `-O0`,
  and plain reductions are fine.
- **Mechanism, confirmed:** the `huge()` identity overflows under the default
  `-fp-model fast`. With `-O3 -fp-model precise` the result is correct.
- **Workaround:** `set_dtbt` reduces `max(Idt_max2)`, then applies the test on the host.
  It's the only one of 26 `reduce` uses with this pattern. The workaround is verified
  correct in the MRE at `-O3`, but it did **not** fix MOM6's `nstep = 0`, which has a
  different cause.

### 8. Staging-buffer overrun in the Level Zero runtime

- **Trigger:**
  - In the default asynchronous command mode, transfers of 16 KiB or less go through
    staging buffers.
  - When one construct submits a **large transfer followed by many small ones**, a small
    transfer can receive the data of the one submitted **64 places later** (a ring of 64
    staging buffers, inferred from a threshold sweep).
- **Why Fortran code hits it:** `!$omp target update to(C)` on a structure with
  allocatable components, inside a mapped parent, becomes:
  - one transfer of `C`;
  - plus one entry per component;
  - plus, after each entry, an 8-byte rewrite of every pointer attached in the parent.

  In `barotropic_init` that was 52,163 small transfers.
- **Reproducer:** `reproducer.F90`, about 130 lines.
  - Parent with 60 mapped allocatable components, and a child of about 290 KB with 60
    allocatable components.
  - **19 of 20 wrong** by default; 0 with `COMMAND_MODE=sync`, with
    `STAGING_BUFFER_SIZE=0`, or with the byte-view workaround.
  - With a small child (no large transfer at the head), nothing goes wrong.
  - The full variant study is in `investigation/`.
- **Symptom in MOM6:** `CS`'s scalars read as -5.829e303 (the bit pattern of a device
  address), so `dtbt` was about 1e19 s and the model stopped with `nstep = 0`.
- **Hidden by `LIBOMPTARGET_DEBUG=1`:** the log slows the host down. That's why every
  debug run worked, and why diagnosis took 13 runs, first as "a race", then "a reduction
  bug", then "optional scalars", then "a layout mismatch".
- **Workaround:** under the macro, `barotropic_init` does
  `c_f_pointer(c_loc(CS), CS_bytes, [storage_size(CS)/8])` and
  `!$omp target update to (CS_bytes)`, which is one map entry. This is correct there
  because none of `CS`'s components are mapped yet.
- **Not yet fixed:** eight other whole-structure `update to(...)` sites have the same shape,
  for example `initialize_MOM` with up to 38,732 small transfers. They haven't failed yet.
  The runtime fallback is `LIBOMPTARGET_LEVEL_ZERO_STAGING_BUFFER_SIZE=0`, which fixes
  every reproducer variant but hasn't been tested on a full MOM6 run.

## Resolved investigation: `nstep+nfilter is 0`

**Answer:** bug 8. Earlier theories were all ruled out along the way:
- the conditional reduction (bug 7, real but not the cause);
- optional scalars made PRIVATE (MRE passes);
- a host/device layout mismatch (offsets measured identical: `BT_OBC` 2904, `dtbt` 47088,
  `bebt` 47128, `BT_Coriolis_scale` 47192, `isdw` 48908 on both sides);
- a kernel launched before the copy landed (the data is wrong before any kernel runs).

The investigation was then handed to an agent, which found the 64-transfer threshold. The
`DBG_DTBT` debug prints used along the way have been removed.

## MOM6 port fixes (not ifx-specific, no macro)

| Fix | Why |
|---|---|
| Duplicate `!$omp declare target` in `MOM_set_viscosity.F90` | Also fixed upstream (`382052827`); dropped from our branch |
| `declare target` on `find_uhbt`, `find_vhbt`, `find_duhbt_du`, `find_dvhbt_dv`, `swap` (`MOM_barotropic.F90`) | Without it, 34 barotropic `do concurrent` loops ran on the host (#5476) against device data |
| `!$omp target data map(to: CS%Hml)` in `extract_surface_state` | `CS%Hml` is a pointer component that is set on the host and was never mapped |
| 5 loops in `step_MOM`/`step_MOM_tracer_dyn` use `associate` names | Stops implicit `tofrom` mapping of all 113 KB of `CS` on every call |

## Git state

The branch is `fix/aurora`, rebased on 2026-11-19 onto `gpu/dev/gpu` (remote `gpu` =
`git@github.com:MOM6-GPU/MOM6.git`, `c914fa41f`, 2026-10-31; 82 commits newer than the
previous base `75b0a161c`). The pre-rebase branch is kept as `fix/aurora-pre-rebase`.
`fix/aurora` is **not pushed**.

| Commit | Content |
|---|---|
| `84aece953` | EOS_Wright: declare target on buggy_Wright elementals |
| `c7144d839` | `IFX_WORKAROUNDS_MOM6` for bug 1 + report |
| `b7d66da25` | `IFX_WORKAROUNDS_MOM6` for bug 2 + report |
| `2ae4115c1` | Bug 3 report (its first workaround version was dropped in the rebase) |
| `85270832d` | Everything since then: bugs 3–8 workarounds, port fixes, reports, `docs/AURORA_README.md` |
| `3c62d63e5` | Wraps 9 new upstream `do concurrent` loops for bug 1 (geothermal, diabatic_aux, kappa_shear, diabatic_driver) |

**Rebase notes:**

- **Continuity:** took upstream's flux-adjust restructure (`21cafbd33`, `aeffba263`), which
  replaces ours, and re-applied `OBC_loc` to its new loops.
- **Intrinsics:** upstream has `declare target` in both the interface and the body of
  `exp_repro` and the new `log_repro`. Under the macro the interface directive is omitted
  for both (bug 3).
- **Upstream ports with `do concurrent` loops not offloaded** (warning #5476), fixed after the
  rebase, so the build now has 0 #5476 warnings:
  - **`MOM_EOS_Roquet_rho.F90`, `MOM_mixed_layer_restrat.F90`:** added `!$omp declare target` to
    the 5 `..._Roquet_rho_loc` procedures and `rmean2ts`. This is correct OpenMP for every
    compiler, so no macro.
  - **`MOM_opacity.F90`:** the loop calls `exp_repro`, whose interface lacks `declare target`
    under the macro (bug 3). Under `IFX_WORKAROUNDS_MOM6` that loop is now an explicit
    `!$omp target teams loop collapse(2)` with the same private variables.

**Verified after the rebase (job 9104777):** double_gyre passes `set_dtbt` and reaches day 1
in the default (async) mode, with no runtime settings. With `COMMAND_MODE=sync` it reaches
day 5 in 17 minutes (healthy). Answers differ from before the rebase in about the 16th
digit, from upstream's numerical changes.

## Batch jobs

Job scripts and output live in `ocean_only/jobs/`, on the shared filesystem. The
scratchpad under `/tmp` isn't visible from compute nodes. They use
`-A mom6_anuga_gpu -q debug -l filesystems=flare -l select=1`.

| Script | What it does |
|---|---|
| `dg.pbs` | Runs double_gyre with `build/MOM6`. Model output goes to `jobs/dg.model.log`. `qsub -v DEBUG=1 dg.pbs` adds `LIBOMPTARGET_DEBUG=1` (about 1.8 GB of log). |
| `run_dg.pbs` | The optional-scalar MRE plus double_gyre. |
| `test_reduce.pbs` | The reduction MRE. |
| `dg_sync.pbs` | double_gyre with `COMMAND_MODE=sync` (no longer needed). |
| `staging_min.pbs` | Bug 8's minimal reproducer: bug, workaround and no-padding builds × three runtime settings. |
| `race_mre*.pbs`, `race_min.pbs`, `race_flat.pbs`, `dg_fix.pbs`, `dg_cmp.pbs` | The agent's bug-8 investigation (`dg_cmp.pbs` uses a 2-day copy of the run directory, `jobs/dg_short/`). |

- **Workflow:** submit with `qsub`, then wait in the background with
  `until [ "$(qstat -xf $J | awk '/job_state/{print $3}')" = F ]; do sleep 20; done`.
- **Turnaround:** a debug-queue job starts and finishes in a few minutes.
- **Building:** builds run on the login node with `make -j` in `ocean_only`.

## Techniques and tools

- **Single-file reproduction:** take the compile line from `make -n <file>.o` in
  `ocean_only/build`, and compile against that directory's `.mod` files. Most ICEs
  reproduce in 1–2 s.
- **Bisecting:** serialize selected `do concurrent` loops, comment out `!$omp target*`
  directives (with continuations), and delta-debug derived-type components.
- **Device code without a GPU:**
  ```bash
  T=/opt/aurora/26.181.0/oneapi/compiler/2026.1/bin/compiler
  $T/clang-offload-bundler -type=o -targets=openmp-spir64 -input=X.o -output=X.dev -unbundle
  $T/llvm-spirv -spirv-ext=+all -spirv-text X.dev -o X.spt
  ```
  - **Kernels:** names carry the source line (`..._l550`), and `FunctionParameter`
    entries give argument counts and sizes (bug 4).
  - **Kernel parameters named `CS`:** show a whole control structure being passed to a
    kernel.
  - **Linkage:** compare `LinkageAttributes ... Import` against `Export` across all
    objects to find unresolved device symbols ("Module link failed", bug 3).
- **Data-transfer map types without a GPU:** compile with `-S`. In the
  `.L.offload_maptypes*` tables, `0x1` = to, `0x2` = from, `0x20` = kernel argument and
  `0x200` = implicit (bug 5).
- **Kernel-argument limit at link time:** `-fopenmp-targets=spir64_gen
  -Xopenmp-target-backend "-device pvc"`. For one object, add
  `-Wl,--unresolved-symbols=ignore-all` and a stub `program`. This does **not** catch
  unresolved device symbols.
- **Reading a core:** `gdb` gives the backtrace. Use `gdb-oneapi` to print Fortran
  derived types; the system gdb crashes on them. Most locals are optimized out at `-O3`.
- **Python:** the system `python3` is 3.6, so run `module load python` first.

## Open items

1. **Run-to-run differences:** answers differ in the last digit between runs, in both async
   and `sync` mode. That breaks MOM6's bitwise reproducibility; find the source (likely an
   unordered reduction or atomic somewhere).
2. **The other eight whole-structure `update to(...)` sites** (bug 8 pattern): fix them in
   the source, or test `LIBOMPTARGET_LEVEL_ZERO_STAGING_BUFFER_SIZE=0` on a full run as a
   blanket fallback.
3. **Profile** with `LIBOMPTARGET_PLUGIN_PROFILE=T` to see where the roughly 1 s per step
   goes. Likely launch overhead on a 44×40 grid, including the extra `flux_adjust`
   launches.
4. **Revisit unneeded workarounds:** the bug-7 reduction rewrite and the optional-scalar
   local copies. Both are harmless.
5. **Known risks not hit in double_gyre:**
   - `horizontal_viscosity` is called without `OBC` by the unsplit solvers.
   - `calc_isoneutral_slopes` is called without `OBC` by ML-MEKE features and
     `meso_sfn_ANN`.
   - 20 allocatable `CS` components are used in kernels without explicit maps.
6. **Commit and file:**
   - one commit per bug, plus the port fixes and the `flux_adjust` restructure;
   - push `fix/aurora`;
   - file reports 1–5, 7 and 8 with Intel. Bug 8 is the most important: silent wrong data.
