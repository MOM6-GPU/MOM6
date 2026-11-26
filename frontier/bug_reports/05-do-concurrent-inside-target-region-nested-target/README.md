# 05: `do concurrent` inside an OpenMP target region is converted to a nested `omp.target` (wrong code)

**Compiler:** AMD flang 24.0.0git, AFAR drop 24.4.0 (ROCm/llvm-project `af5d6a9790939cc301486abeec5a51ee48f59c18`)
**Severity:** silent wrong results on **valid code** (-O2); GPU memory fault at -O0; libomp assertion in host fallback.
**Needs:** `-fopenmp --offload-arch=gfx90a -fdo-concurrent=device`, a GPU to see the result.

## Summary
With `-fdo-concurrent=device`, `DoConcurrentConversionPass` (`omp-do-concurrent-conversion{map-to=device}`)
converts **every** `do concurrent` into `omp.target { teams { parallel { distribute { wsloop }}}}`, including
one that is already inside an `!$omp target` region. The result is an `omp.target` nested in an
`omp.target`, which is not valid OpenMP, but nothing diagnoses it. On the GPU the inner loop never runs.

Every enclosing construct tried behaves the same: `target`, `target teams`, `target teams loop`,
`target teams distribute`, `target teams distribute parallel do`, `target parallel loop`.
A `do concurrent` nested in a top-level `do concurrent` is fine; so is `-fdo-concurrent=host`/`none`.

## MRE
```fortran
  a = 1.0
  !$omp target map(tofrom: a)
  do j = 1, nj
    do concurrent (i=1:ni)
      a(i,j) = a(i,j) + real(i+j)
    enddo
  enddo
  !$omp end target
```
`./run.sh` (on a GPU node, or `RUN="srun --jobid=<id> --overlap -n1 --gpus=1" ./run.sh`):
```
== mre_target_region -O2:  mre_target_region 1600. WRONG          (expected 67200: inner loop skipped)
== mre_target_region -O0:  mre_target_region 1600. WRONG
== mre_teams_loop -O2:  teams_loop 1600. WRONG
== mre_teams_loop -O0: Warning: Queue error - HSA_STATUS_ERROR_MEMORY_FAULT
== mre_teams_loop -O2, OMP_TARGET_OFFLOAD=DISABLED: OMP: Error #13: Assertion failure at kmp_csupport.cpp(652).
== IR after omp-do-concurrent-conversion (nested omp.target):
    omp.target kernel_type(generic) map_entries(%16 -> %arg0
        omp.target kernel_type(spmd) host_eval(%63 -> %arg3,
```
Host fallback stack: `__kmpc_fork_teams` -> `__kmp_join_call` -> `__kmpc_end_serialized_parallel` -> assert.

## Expected
A `do concurrent` inside a target region should be left as a loop (or mapped to `parallel do`/`simd`
inside the existing kernel), never wrapped in another `omp.target`. At minimum, a diagnostic.

## Hit in MOM6 (dev/gpu)
50 loops in 4 files: `MOM_tracer_advect.F90` (30), `MOM.F90` (9, `extract_surface_state`),
`MOM_diabatic_aux.F90` (7), `MOM_isopycnal_slopes.F90` (4). Found with a scan of `!$omp target` regions.

## Workaround
Replace the inner `do concurrent` with a plain `do` (the enclosing construct still parallelizes the
outer loop). Not yet applied in MOM6.
