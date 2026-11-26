# Compiler workarounds for building MOM6 (dev/gpu) with AFAR 24.4.0 on Frontier.
# Every entry points at a reproducer in bug_reports/. Per-file flags use `private` so that they are
# not inherited by prerequisites (e.g. everything MOM.o depends on). Pass this as an extra makefile:
#   make -C build -f Makefile -f ../../src/MOM6/frontier/afar_workarounds.mk MOM6   (from ocean_only)

# Source-level workarounds. They sit in the MOM6 source as
#   #ifdef AMD_WORKAROUNDS / workaround / #else / original / #endif
# so `grep -rn AMD_WORKAROUNDS src` lists them all. Without this define the original code is built.
#   bug_reports/01: MOM_interface_heights.F90 (find_rho_bottom_2d),
#                   MOM_set_viscosity.F90 (set_viscous_BBL, set_viscous_ML): renamed loop indices.
#   bug_reports/06: MOM_coms.F90 (reproducing_sum): array reduction as an OpenMP construct.
FCFLAGS += -DAMD_WORKAROUNDS

# bug_reports/01: omp.private / fir.local privatizer name clash.
# Non-delayed OpenMP privatization creates no omp.private symbols, so nothing clashes.
# (Not usable for MOM_set_viscosity.F90: with this flag a combined target construct with firstprivate
#  hits "not yet implemented: Unhandled clause FIRSTPRIVATE in TARGET construct".)
NO_DELAYED_PRIV = -mmlir --enable-delayed-privatization=false
BUG01_OBJS = MOM_tracer_advect.o MOM_kappa_shear.o MOM_wave_speed.o MOM_continuity_PPM.o \
             MOM_lateral_mixing_coeffs.o MOM_set_diffusivity.o MOM_mixed_layer_restrat.o \
             MOM_tracer_hor_diff.o MOM.o
$(BUG01_OBJS): private FCFLAGS += $(NO_DELAYED_PRIV)

# bug_reports/04: -g + nested do concurrent reductions -> "conflicting debug info for argument".
BUG04_OBJS = MOM_tracer_advect.o
$(BUG04_OBJS): private FCFLAGS += -g0

# bug_reports/02: concurrent printing of ops in diagnostics (warnings from the loop->simd rewrite,
# verifier errors) corrupts the heap in fir::RecordType::print and crashes flang at random.
# Run MLIR single-threaded so builds are deterministic.
FCFLAGS += -mmlir --mlir-disable-threading
