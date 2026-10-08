# RC1.26 Build89 — Bounded GGML scheduler metadata

## Build88 observed
On iPad Pro M5 12GB, 32K, `malloc(550227616)` returned NULL; `mmap` also failed with errno=12 (ENOMEM). Build88 avoided a crash but could not create the local OpenAI API context.

## Rationale and code
Pinned Prism reserves the worst case `graph_size*GGML_SCHED_MAX_SPLIT_INPUTS*2*sizeof(ggml_tensor)+graph_overhead`. At 27232 graph nodes this requests about 525 MiB, even though the first fused GDN graph has 4831 compute nodes.

In split-graph logic, metadata copies are keyed to tensor identity and target backend/copy slot; each cross-backend copy can additionally create a dependency view. Build89 leaves the original malloc unchanged. ONLY when that malloc fails, on Apple during experimental 32K context init, retry with conservative compact capacity:

```
capacity = sched->hash_set.size * (2*n_backends*n_copies+2)
         * ggml_tensor_overhead()
         + ggml_graph_overhead_custom(graph_size, false)
         + 1 MiB
```

Using the scheduler **hash entry capacity**, not the first graph size, avoids underestimating later prompt/tokens graphs. Includes GGML object headers. On compact malloc failure, the existing Build88 mmap fallback retries the smaller amount and still guards double allocation failure. All KV, GDN, GPU layers, 16K policies and model semantics remain unchanged.

The new `BUILD89_META_USED bytes=... capacity=...` checkpoint audits actual scheduler metadata usage. 32K is not certified without real-device text/vision/multi-turn/SSE/restart validation.

## Next real-device test
Install the successful Build89 IPA; select 32768 and start the API **once**. If it starts, test /v1/models, a 32-token text request, then a 256-token text request. Copy diagnostic + full native trace. If it cannot start, copy complete trace and return to 16384.

Expected: `BUILD87_SCHED_BUFFER_ALLOC ... buffer_nonnull=0`, `BUILD89_COMPACT_BUDGET`, `BUILD89_COMPACT_ALLOC_SUCCESS` (or `BUILD88_MMAP_SUCCESS` on the compact size), `BUILD87_SPLIT_GGML_INIT_DONE`, `BUILD89_META_USED`, `BUILD84_CTX_SCHED_DONE`.
