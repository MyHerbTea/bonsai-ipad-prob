# RC1.26 Build 85 — Scheduler Reserve Isolation

## Real-device findings from Build 84

* iPad Pro M5, iPadOS 27.0.1, context=32768: app terminated during `llama_context::sched_reserve()`.
* 16 full-attention KV shards (3, 7, 11, ..., 63) actually executed.
* All 16 shards succeeded allocation/clear; 37,748,736 bytes each, 576 MiB total.
* `BUILD84_CTX_MEMORY_DONE` recorded. `BUILD84_CTX_SCHED_BEGIN` recorded, but no scheduler completion.
* These results exonerate the KV sharding/zero-fill code as the **immediate** crash location.

## Build 85 change

Build85 **does not claim to fix 32K**. No graph, scheduler, KV arithmetic, offload, quantization or weight parameters are changed. The pinned Prism source remains `adfffbe41...`; Build83 and Build84 patches run first. Build85 adds crash-persistent stage markers within `llama_context::sched_reserve()` and `graph_reserve()` via the Build84 fsync trace primitive.

Steps cover graph_max_nodes, result memory allocation, scheduler construction, memory->init_full, fused GDN resolution, prompt graph #1, token graph, prompt graph #2, graph building and backend reservation.

## Device test

1. Install the Build85 artifact from the matching successful GitHub Actions run.
2. Verify 16K if desired. Do not change frozen 16K runtime policy.
3. Select 32768 and start API once. If the app terminates, restart it.
4. Copy the full snapshot including `[BUILD 84 NATIVE CONTEXT CRASH TRACE]` (this header remains for backwards-compatible log readers).
5. The last `BUILD85_...` marker differentiates fused-op failure, model graph creation, scheduler graph split, or Metal backend allocation.

16K is the recovery configuration. Only certify 32K once actual device inference, vision, restart and stability pass.
