# 02: flang crashes at random: heap corruption in `fir::RecordType::print` from multithreaded diagnostics

**Compiler:** AMD flang 24.0.0git, AFAR drop 24.4.0 (ROCm/llvm-project `af5d6a9790939cc301486abeec5a51ee48f59c18`)
**Severity:** ICE on **valid code**, non-deterministic. The same command fails or succeeds from run to run.
**Hit in MOM6:** `MOM_continuity_PPM.F90` (47 such warnings), `MOM_tracer_advect.F90`, `MOM.F90`.

## Summary
MLIR runs some passes and the verifier on several functions in parallel (`llvm::StdThreadPool`).
When a diagnostic attaches an op (`emitWarning`/`emitError` -> `Diagnostic::operator<<(Operation&)`),
the op is printed, and printing walks the FIR derived types. `fir::RecordType::print` keeps a set of
record types already being printed, to stop infinite recursion. When several threads print at
once, that set is corrupted (`SmallPtrSetImplBase::Grow` -> `free`), and the process aborts with
`double free or corruption`, `corrupted size vs. prev_size`, or a segfault.

The diagnostic that is enough to trigger it is an ordinary **warning**, from the generic-loop
conversion:
```
warning: Detected standalone OpenMP `loop` directive with thread binding, the associated loop will be rewritten to `simd`.
```
In the build logs, the text of these warnings comes out interleaved character by character, which
shows that several threads print at the same time.

## MRE
`gen_mre.py` writes `mre_parallel_warning_print.f90`: 64 procedures, each with a standalone
`!$omp loop` nested in `!$omp target` (which gives the warning above) that reads through a cycle of
40 derived types (`t0 -> t1 -> ... -> t0`, pointer components):
```fortran
  subroutine s0(x, a, ni, nj, nk)
    type(t0), intent(in) :: x
    ...
    !$omp target map(tofrom: a)
    do k = 1, nk
      !$omp loop collapse(2)
      do j = 1, nj ; do i = 1, ni
        a(i,j,k) = a(i,j,k) + x%p%v(i,j)
      enddo ; enddo
    enddo
    !$omp end target
  end subroutine s0
```
`./run.sh` compiles it 8 times with `-c -O2 -fopenmp --offload-arch=gfx90a`, then 4 times with
`-mmlir --mlir-disable-threading`. Typical output:
```
run 1: double free or corruption
run 2: double free or corruption
run 3: no crash
...
run 7: double free or corruption
run 8: no crash
with -mmlir --mlir-disable-threading (x4): ok ok ok ok
```

## Stack (MOM_continuity_PPM.F90)
```
corrupted size vs. prev_size while consolidating
 #9 _int_free
#10 cfree
#11 llvm::SmallPtrSetImplBase::Grow(unsigned int)
 ... fir::RecordType::print / fir::PointerType::print / fir::BoxType::print, repeated ...
#66 mlir::Diagnostic::operator<<(mlir::Operation&)
#67 mlir::OpState::emitWarning(llvm::Twine const&)
#68 GenericLoopConversionPattern::rewriteToSimdLoop(mlir::omp::LoopOp, ...)
#69 GenericLoopConversionPattern::matchAndRewrite(mlir::omp::LoopOp, ...)
 ...
#77 GenericLoopConversionPass::runOnOperation()
```
The same crash also comes from the verifier, `verifyPrivateVarList<mlir::omp::LoopOp>` ->
`OpState::emitError`, when bug 01's errors are reported (`MOM_tracer_advect.F90`, `MOM.F90`).
`crash-reproducer/` holds the files flang wrote for `MOM_tracer_advect`.

## Workaround
`-mmlir --mlir-disable-threading`. `afar_workarounds.mk` adds it for every file.
