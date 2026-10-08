# RC1.26 Build88 — Scheduler mmap Recovery (experimental)

## Direct Build87 real-device proof

The M5 12GB iPad returned NULL when Prism's GGML backend scheduler tried to malloc 550,227,616 bytes (524.74 MiB) for its overly conservative *metadata graph context buffer*.

```
BUILD87_SCHED_BUFFER_ALLOC bytes=550227616 buffer_nonnull=0
BUILD87_SPLIT_GGML_INIT_BEGIN bytes=550227616 external_buffer_nonnull=0
```

GGML's `ggml_init` tries to allocate the same size internally if no buffer is supplied; this was the crash boundary. This does not prove the underlying 550MiB would have been used in practice.

## Narrow fix

* Keep the **same scheduler metadata capacity and all graph semantics**; do NOT shrink the graph max nodes or split budget.
* ONLY on Apple, ONLY if the original malloc returns NULL, and ONLY when Build84's experimental >=32K trace latch exists, try `mmap(MAP_PRIVATE|MAP_ANON, PROT_READ|PROT_WRITE)`.
* Anonymous memory mapping reserves contiguous virtual address space, with pages typically becoming resident when touched; its virtual size alone is not physical footprint.
* Track mmap ownership and release via `munmap`; preserve original `free` for original malloc.
* If both allocations fail, release early scheduler constructor allocations and return NULL. The C++ caller checks before proceeding and throws; this prevents `ggml_init` attempting another 550MiB allocation. It does not guarantee an App-level catch if other platform-level memory conditions terminate the process.
* No change to 16K, KV sharding, fused op policy, 32K GPU layers, output, or model.

## Real-device acceptance

Install Build88 after CI PASS, start 32K once. Trace outcomes:

* `BUILD88_MMAP_SUCCESS` followed by `BUILD87_SPLIT_GGML_INIT_DONE`: allocator bottleneck crossed.
* `BUILD88_MMAP_FAILURE`: mapping not available; do not assume 32K can work.
* `BUILD84_CTX_SCHED_DONE` and `MODEL_08_CONTEXT_CREATE_DONE`: native 32K context created, but inference still must be certified.
* Perform text request, 1–3 image vision, follow-up text, streaming/nonstreaming, UTF-8/JSON, cold restart and 16K regression before declaring 32K PASS.

Use `复制完整原生崩溃追踪（当前及上次）` after any crash. iPadOS .ips is still needed to prove the OS-level termination reason.
