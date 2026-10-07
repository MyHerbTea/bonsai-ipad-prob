# RC1.26 Build 82 — Unified-Metal 32K Lab

Build 79 passed 8192/Q8/99 GPU layers and 16384/Q4/56 GPU layers at roughly the same ~6.1 GiB Metal allocation. Build 80 (40 layers) and Build 81 (24 layers) both terminated at MODEL_07_CONTEXT_CREATE_BEGIN, including fresh-process 32K.

Build 82 tests the opposite hypothesis: on Apple unified memory + mmap, partial CPU/Metal placement does not recover discrete-GPU-style physical memory and may increase scheduler/host-buffer splits. 32K therefore uses one Metal backend: Q4_0, 99 GPU layers, batch/ubatch 4/4, Flash Attention ON, KQV/Op offload ON, kv_unified unchanged, mmap ON, threads <=4. The validated 16K route remains unchanged.

The diagnostic snapshot now records the effective policy and engine parameters plus pre-context memory/Metal evidence so a system termination can be diagnosed after relaunch.
