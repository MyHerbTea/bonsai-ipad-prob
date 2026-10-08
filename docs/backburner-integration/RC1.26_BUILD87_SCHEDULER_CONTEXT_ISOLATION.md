# RC1.26 Build87 — scheduler GGML context initialization isolation

## Grounded failure evidence
Build86 real device trace on 2026-10-08:
* context=32768, model loaded, Metal KV shards 16/16 success, fused GDN (autoregressive) graph built with 4,831 nodes.
* `BUILD86_SPLIT_ENTER nodes=4831 leafs=993 backends=3 hash_size=32771 context_bytes=550227616`
* No subsequent `BUILD86_SPLIT_PASS1_BEGIN`. Crash therefore preceded backend-assignment pass 1.
* Source segment between these markers: reset scheduler split fields, `ggml_free(sched->ctx)`, `ggml_init(params)`, `graph->uid = ggml_graph_next_uid()`.
* Scheduler reserves a ~524.7 MiB malloc context buffer. Its successful allocation, alignment, and initialization have **not** been established by the prior trace.

## Build87 actual changes
* Additional evidence-only checkpoints in GGML scheduler creation and `ggml_backend_sched_split_graph()`: whether 525 MiB buffer malloc returned non-null; splitter reset, prior context free, ggml context init and graph UID assignment.
* No changes to GDN fusion, KV, model weights, GPU layer count, graph scheduling or 16K baseline; trace enabled only when context >=32768 via existing App/Prism environment latch.
* Keeps Build86 complete native trace copy UI, prior trace backup and full forensic summary.
* This is **not a 32K fix** until real device evidence confirms cause and a targeted fix passes tests.

## Device test
Install successful GitHub Actions Build87 IPA via existing signing method. Start 32K API exactly once. If crash, relaunch App and copy "复制完整原生崩溃追踪（当前及上次）". Record the last `BUILD87_*` event. Recover API by selecting 16K.

## Interpretation
* `SCHED_BUFFER_ALLOC buffer_nonnull=0`: native malloc allocation failure, pending safe handling.
* `SPLIT_CTX_FREE_BEGIN` without DONE: previous GGML context destruction; inspect possible pointer corruption.
* `SPLIT_GGML_INIT_BEGIN` without DONE: GGML context initialization, memory pressure, allocator assertion or jetsam.
* `SPLIT_UID_BEGIN` without DONE: graph UID generation failure.
* `SPLIT_UID_DONE` without `BUILD86_SPLIT_PASS1_BEGIN`: narrow boundary to pass1 dispatch.
iPadOS .ips is still needed to distinguish abort, bad access, and OS memory termination.
