# RC1.26 Build 81 — 32K Memory Squeeze

Build 79 passed 6144, 8192 and 16384 on the iPad Pro M5 12 GB. Build 80 showed that 32768 still terminates even on a clean-process cold start, so Build 81 treats 32K as a context-create peak-memory problem.

16K remains on the validated Build 79 profile.

32K capacity-first profile: Q4_0 KV, mmap, Flash Attention, <=24 GPU layers, <=4/4 batch/uBatch, CPU KQV/op execution, <=4 context threads.

64K escalation profile: Q4_0 KV, mmap, Flash Attention, <=8 GPU layers, <=2/2 batch/uBatch, CPU KQV/op execution, <=2 context threads.

The goal is to establish capacity first. After a 32K PASS, throughput can be recovered by increasing GPU residency and batch size one dimension at a time.
