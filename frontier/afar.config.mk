# MOM6 / ocean_only build configuration -- AMD LLVM toolchain, OpenMP offload
# to MI250X (gfx90a).  AMD analogue of sample.config.mk (which targets NVHPC).
#
# Activate with:   cp ../src/MOM6/frontier/afar.config.mk config.mk   (from ocean_only)
# (the Makefile does `-include config.mk`)
#
# Requires:  source ../src/MOM6/frontier/afar_env.sh  (sets MOM_DEPS and ROCM_PATH)

MOM_DEPS ?= $(error MOM_DEPS is not set: source frontier/afar_env.sh)
ROCM_PATH ?= $(error ROCM_PATH is not set: source frontier/afar_env.sh)

CC    = $(ROCM_PATH)/bin/amdclang
MPICC = $(MOM_DEPS)/bin/mpicc
FC    = $(ROCM_PATH)/bin/amdflang
MPIFC = $(MOM_DEPS)/bin/mpifort
PYTHON = python3

# Offload target.  gfx90a = MI250X (Frontier).
OFFLOAD_ARCH = gfx90a

# -fopenmp                 enable OpenMP (required by -fdo-concurrent=device)
# --offload-arch=gfx90a    generate device code for MI250X
# -fdo-concurrent=device   map `do concurrent` loops onto OpenMP target regions
#                          (AMD analogue of NVHPC's -stdpar=gpu)
OFFLOAD_FLAGS = -fopenmp --offload-arch=$(OFFLOAD_ARCH)

# __NVCOMPILER_OPENMP_GPU: nvfortran predefines it, flang does not. dev/gpu uses it as its
# "GPU build" switch: whole-domain blocking defaults, fixed-size kappa_shear work arrays, and no
# do_any early-exit inside target regions (which otherwise blocks every k iteration).
FCFLAGS = -g -O2 $(OFFLOAD_FLAGS) -fdo-concurrent=device -D__NVCOMPILER_OPENMP_GPU

# FMS is built WITHOUT do-concurrent offload, mirroring the NVHPC sample
# ("FMS cannot currently accept -stdpar=gpu").  It still gets plain OpenMP
# offload so the runtime and module ABI stay consistent with MOM6.
FMS_FCFLAGS = -g -O2 $(OFFLOAD_FLAGS)

LDFLAGS = $(OFFLOAD_FLAGS)

#-----------------------------------------------------------------------------
# Optional knobs
#-----------------------------------------------------------------------------

## Bitwise-reproducibility / debugging: disable vectorisation and FMA
## contraction (the AMD analogue of NVHPC's -Mnovect -Mnofma).
#FCFLAGS     += -fno-vectorize -ffp-contract=off
#FMS_FCFLAGS += -fno-vectorize -ffp-contract=off

## Offload diagnostics (closest thing to NVHPC's -Minfo=all).
#FCFLAGS += -Rpass=openmp-opt -Rpass-analysis=openmp-opt -Rpass-missed=openmp-opt

## Unified shared memory instead of separate device memory.  The NVHPC sample
## uses -gpu=mem:separate, which is what plain gfx90a already gives you.  For
## managed/unified memory on MI250X, request XNACK and export HSA_XNACK=1 at
## run time:
#OFFLOAD_ARCH = gfx90a:xnack+

## Drop to -O0 to match the sample's debug settings.
#FCFLAGS     := $(subst -O2,-O0,$(FCFLAGS))
#FMS_FCFLAGS := $(subst -O2,-O0,$(FMS_FCFLAGS))

# NOTE: sample.config.mk adds -Minline=name:flux_elem,... for
# MOM_continuity_PPM.F90.  amdflang has no per-symbol inlining flag; it relies
# on the LLVM inliner at -O2.  If continuity kernels underperform, that is the
# first place to look.
