# ifx: reading derived-type components through associate names in a kernel (not a bug)

**Status: not reproduced, and not needed.** `run.sh` prints `PASS` at `-O0` and `-O3` on
the GPU: reading `G%IareaT * G%dy_Cu` through associate names gives the same values as
reading through `G%`.

This was written while testing associate names in MOM6's continuity kernels as a way to stop
ifx mapping all of `G` at every launch. That experiment changed the answers, and the GPU
answers of that time were later found to be wrong for other reasons. So the answer change
doesn't point to a bug in associate *reads*.

Associate names do have a real bug, but for *writes*: see `../ifx_associate_write_lost`.

## Environment

- Compiler: `ifx (IFX) 2026.1.0 20260617`
- System: Aurora (Intel GPU, `spir64` offload target)
