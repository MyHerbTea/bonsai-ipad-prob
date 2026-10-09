# Build 94 — PTQ1_0 Metal Dispatch Boundary: AI B Independent Review Packet

**Status: RESEARCH / REVIEW ONLY.** No engine parameters, native code, CI settings, signing or device state have been changed for Build 94.
Created 2026-10-09. Starting source: Build93 P0 `2af62f721395348110551f8b7298c2f97c12b5f5`, GitHub Actions run `37925711616` succeeded. Frozen Build92 baseline remains separate.

## 1. Goal and verified device evidence

Target: **Ternary-Bonsai-2-27B-PTQ1_0.gguf**, iPad Pro 11 M5 / 12 GB RAM, native Prism/Metal, OpenAI-compatible local API, **n_ctx=32768**, Q4_0 K/V cache, model mmap, gpu layers=99. Preserve text+vision API and stable 32K initialization.

- Build92 context 32768, `n_batch=n_ubatch=4`: ~7300 prompt tokens; still evaluating at ~884 tokens after ~133s. Observed ~6–7 input tokens/s, not completed TTFT. Client ~122s timeout did not stop server execution.
- Build93 P0 `n_batch=n_ubatch=8`: a **1192-token** request finished in ~179.56s wall time (~176.5s inference; reported ~6.75 prompt tokens/s), 9 output tokens, no active requests left, candidate confirmed, no fallback, nominal thermals before/after, Metal allocated ~6528 MiB before/after, but not peak sampled.
- **Comparison caveat**: Build92 ~7300 vs Build93 1192 is *not* a controlled A/B, and Build92 never completed; apparent 2% variation does NOT establish speedup or slow-down. The measured Build93 batch8 result refutes a confidently predicted 2x uplift from solely doubling 4->8 in that tested setting.
- Current observer bug: `observeNativeTextPrefill()` sets `native_batch_last_completed_ms = durationMs` even on `decode_begin` (`durationMs=0`), erasing last completed latency. No ground truth histogram of batch durations yet.

## 2. Reusable historical device tests (do NOT treat as 32K proof)

Documents already in this repository:
- `docs/backburner-integration/RC1.26_BUILD72_PHASE2D_DEVICE_EVIDENCE.md`: 614-token fixed prompt on that build, 8/8 avg prefill **85,948.521ms** vs 16/16 **28,113.818ms** (3.06x).
- `docs/backburner-integration/RC1.26_BUILD73_PHASE2E_DEVICE_EVIDENCE.md`: 16/16 **23,020.009ms** vs 32/32 **11,789.429ms** (1.95x).
- `docs/backburner-integration/RC1.26_BUILD74_PHASE2F_DEVICE_EVIDENCE.md`: 32/32 **11,741.664ms** vs 64/64 **10,729.679ms** (8.6% faster prefill; substantial decode regression), so 32 was preferred.
- These tests controlled their *within-build* pairs including prompt, process launch, model, seed and Metal Tensor disabled. **They were NOT verified under current Build93 32K Q4/99-layer runtime.** Historical GPU/context/Metal configuration and artifacts must be checked before cross-generation inference.
- Build79 memory policy aimed at 32K Q4 KV, <=40 GPU layers, <=8/8; 32K API cold start later crashed. Build81 chose 4/4 as capacity-first. Build82 moved to unified Metal 99 GPU layers + Q4/4x4 to avoid partial CPU/Metal split, with history of model/context initialization failures. Thus neither `8/8 is guaranteed safe everywhere` nor `16/16 is impossible` is justified.

## 3. Pinned native backend and source-level candidate mechanism

Build93 workflow `.github/workflows/build-ios.yml` builds:
- `https://github.com/PrismML-Eng/llama.cpp` pinned SHA **`adfffbe41b2cabcd51fff326ab045662265062bb`** (2026-09-25).
- Applies repository Build83-89 KV/scheduler/mmap/native diagnostic patches; results MUST be analyzed on this exact patched native build, not assumed equal to unmodified upstream.

At pinned Prism SHA:
- `ggml/src/ggml-metal/ggml-metal-ops.cpp`, `ggml_metal_op_mul_mat` around lines **2791–2910**:
  - For F32 activations and weight types including `GGML_TYPE_PTQ1_0`, a small-batch `mul_mv_ext` branch is selected if its conditions pass and `2 <= ne11 <= 8`.
  - The conventional `mul_mm` branch requires layout support, `has_simdgroup_mm`, `ne00 >= 64`, and `ne11 > ne11_mm_min`, where `ne11_mm_min=8` for non-`Q1_0`.
  - Thus for eligible dense PTQ1 matrix operations, the transition **8 -> 9+** is a genuine *source-level dispatch boundary* worth testing.
- `ggml/src/ggml-metal/ggml-metal-device.cpp` around **885–889**:
  - `ggml_metal_ptq1_multicol_enabled` requires env `GGML_METAL_PTQ1_MULTICOL=1`, type PTQ1_0/F32, valid layout, and `2 <= ne11 <= 4`; not enabled by default.
  - **Do not confuse** PTQ1 opt-in multicol mat-vec, default mul_mv_ext small-batch, and conventional mul_mm.
- Exact paths:
  - https://github.com/PrismML-Eng/llama.cpp/blob/adfffbe41b2cabcd51fff326ab045662265062bb/ggml/src/ggml-metal/ggml-metal-ops.cpp#L2790-L2915
  - https://github.com/PrismML-Eng/llama.cpp/blob/adfffbe41b2cabcd51fff326ab045662265062bb/ggml/src/ggml-metal/ggml-metal-device.cpp#L885-L891
- **Hypothesis, not a verified runtime fact**: batch4 & batch8 primarily use the inefficient small-batch dispatch; batch16/ubatch16 can enable mul_mm for applicable PTQ1 ops and amortize work. Counterhypotheses: not all layers use PTQ1; PTQ1-specific matmul could route otherwise; context lengths and KV traffic dominate; graph shape/strides prevent mul_mm; fallback or CPU scheduling differs; native code patches influence dispatch. Need actual kernel-route evidence, not inferred from a source `if` statement.

Independent evidence:
- ggml-org/llama.cpp issue #25250 discusses a Metal small-batch performance gap around 4–16 and route break-even. https://github.com/ggml-org/llama.cpp/issues/25250
- Upstream batch/ubatch semantics: `n_batch` is a logical cap per `llama_decode`, `n_ubatch` the physical compute bound. https://github.com/ggml-org/llama.cpp/discussions/6328 ; https://github.com/ggml-org/llama.cpp/blob/master/tools/batched-bench/batched-bench.cpp

## 4. Upstream updates: do not upgrade fork indiscriminately

The pinned SHA predates:
1. Prism 2026-09-28 `79971a480be61252ef12fb51d08666de754f3c81`: Metal SwiGLU+Hadamard fusion / Qwen last-row narrowing. Reported M5 Pro Bonsai PTQ/PQ2 configurations show **modest** PP512 improvement; model-specific routing must be validated.
2. Prism 2026-09-29 `445fa82098e77b6da927e0251d8636001ac12c2c`: GDN state row SIMD optimization; potential architecture overlap but no proof of 32K M5 PTQ1 prefill gain.
3. Prism 2026-10-08 `5e9365f05e56c7d28ff596c874dcffa3da785b15`: PTQ1 **dense mat-vec** output rows 4->5 (MUL_MAT_ID remains four due numerical differences); published gain is primarily **decode** (M1 Max 10.300->11.505 tg128), not established 32K prefill gain.
4. Other 2026-09-29 PQ2_0 DFlash few-row pathways are **different quantization / speculative-use cases**. Not immediately transferable to the chosen PTQ1_0 27B.

Reference commits:
- https://github.com/PrismML-Eng/llama.cpp/commit/79971a480be61252ef12fb51d08666de754f3c81
- https://github.com/PrismML-Eng/llama.cpp/commit/445fa82098e77b6da927e0251d8636001ac12c2c
- https://github.com/PrismML-Eng/llama.cpp/commit/5e9365f05e56c7d28ff596c874dcffa3da785b15

**No runtime, kernel or model change in the same experiment as changing batch to 16.** Candidate cherry-picks require separate benchmarks after 16/16 inference is understood.

## 5. Specific independent review questions for AI B

### Q1: Precise dispatch proof or falsification
- For PTQ1_0 on current pinned Prism SHA (including Build83-89 patches), trace `ggml_metal_op_mul_mat` for `ne11=4,8,16`, plus odd/partial-tail batch sizes. Which kernels actually execute, with which shape and reason? Are any layers using special `MUL_MAT_ID`, GDN, FWHT, CPU fallback, or strides that invalidate a simplistic threshold claim?
- Does `ggml_metal_ptq1_multicol_enabled` default false? Is environment ever set by Bonsai? Explain whether enabling it would confound (and should remain OFF) for P0.

### Q2: Historical evidence transferability
- Reconstruct Build72–74 experiment context length, GPU layers, model quant format, Metal Tensor state, exact prompt hash, KV/cache state, and decode settings. Mark every undocumented value as **unknown** rather than guessing.
- Explain why those runs had strong 8->16->32 improvements while Build92/93 at 32K remain ~6–7 tok/s; rank hypotheses with expected discriminating evidence.

### Q3: Minimal instrumentation with low overhead
- Fix Build93 last-batch latency being reset at `decode_begin`; capture total llama_decode wall duration, batch count, token count, current in-flight elapsed, average/p50/p95 batch latency or bounded histogram, and actual effective batch/ubatch.
- Strongly prefer **aggregate counters or one-time kernel route classification** rather than synchronous per-layer disk I/O, per-op printf or excessive memory.
- Distinguish CPU wall time, GPU synchronization/queued work, KV prefix reuse, warmup, memory/thermal trends; ensure timing metric is correctly named and not misrepresented as GPU execution time if asynchronous.

### Q4: Safe narrow Build94 P0 device matrix
- **8/8 baseline and 16/16 candidate only** at exactly 32768, with unchanged PTQ1, KV Q4, 99 GPU layers, offload flags, pinned Prism. 16/8 is a secondary diagnostic candidate only if evidence warrants.
- Target a common **real-tokenized** deterministic prompt of 256 then 512–650 tokens; budget requests so no default ~7300 long-run. Report exact tokenize count, no cross-request KV reuse, compare same task/hash/process state, with user-friendly one-run driver.
- How should switching require a fresh llama context and safe process restart without manually signing or reinstalling per arm?
- Keep 4/4 safe rollback available; include failure-stage markers and a tri-state verdict: PASS / FAIL / INCONCLUSIVE. Do not claim that failure implies Jetsam.
- Deal with existing Build93 candidate trial sticky recovery / process-scoped latch so baseline and candidate are selectable by an explicit, validated experiment arm. Unclean/missing marker must not overwrite successful enrollment or create a permanent lockout.

### Q5: Thresholds and rollout
- Specify a realistic *relative* speed gate on same prompt, not fictional fixed t/s or a TTFT improvement against a request that never completed.
- Include short-prompt quality and decode regression gates, memory pressure/stability hard stops; two clean starts if needed, fewer if unsafe.
- Keep Build93 unchanged and audited; propose whether Build94 is experiment-only until device signoff. Do not promote 16/16 by static CI evidence.

### Q6: Separate fork-update roadmap
- Should Build94 avoid all upstream cherry-picks until 16/16 device data arrives? If not, which single commit and what clear proof of merit/compatibility with Build83–89 patches and bundled xcframework?

## 6. Deliverables AI B must return

1. One-paragraph verdict: whether `16/16` is the correct next experiment and major caveats.
2. Kernel-path decision table for `ne11=4,8,16`, labeled `proven from source` vs `needs device trace`.
3. Ranked root-cause hypotheses and discriminating measurements.
4. Minimal viable Build94 change set (exact functions and integration points, pre/post conditions).
5. A safe arm-selection and recovery state machine.
6. A short device certification matrix (same prompt, no 7300 default), stopping conditions and comparability safeguards.
7. Identify unacceptable assumptions in AI A's proposal; no claims of 2x speedup or negligible memory growth absent evidence.
8. Recommendations for upstream commits to **defer**, with version/rebase risk.

The implementation phase begins only after this review; source Build93 is already certified as a **buildable experimental diagnostic**, not product Stable.
