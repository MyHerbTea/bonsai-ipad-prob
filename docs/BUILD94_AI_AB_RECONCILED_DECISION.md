# Build 94 — AI A / AI B source-reconciled decision (2026-10-09)

**State: review accepted with critical factual corrections; NO runtime modifications, experimental IPA, or device certification claimed.** Branch starts at Build93 compiled P0 SHA `2af62f721395348110551f8b7298c2f97c12b5f5`, Prism pinned to `adfffbe41b2cabcd51fff326ab045662265062bb`.

## 1. AI B advice accepted
- Fix the Build93 `native_batch_last_completed_ms` overwritten at `decode_begin` and expose bounded aggregated per-request timings.
- A/B must use identical *actually tokenized* prompt and generation budget; keep model, 32768 context, Q4 KV, 99 GPU layers, mmap, offload settings and pinned Prism identical. Prevent KV prefix reuse and gate thermal/memory.
- Keep 4/4 recoverable, never infer Jetsam from a stale marker alone, do not auto-promote 16/16 to production, do not upgrade Prism in the same build.
- Use 256- and optionally 512-650-token requests, not an expensive 7300-token loop.

## 2. Major technical corrections to AI B report

### WRONG: `ne11` represents parallel sequences and equals 1 throughout prefill
In the *pinned* GGML `ggml_mul_mat(a,b)`, operand `b` is shaped `[k,m]`; the Metal backend explicitly sets `ne11` from `op->src[1]->ne[1]`, i.e. the row count of **that specific right-hand tensor**, not `n_seqs`. Dense hidden-state matmuls can have one activation row per token during prefill. The graph can have other layouts/reshapes too; **do not assume `ne11==n_batch` for every operator either.** Need actual per-op shape observations.
- https://github.com/PrismML-Eng/llama.cpp/blob/adfffbe41b2cabcd51fff326ab045662265062bb/ggml/include/ggml.h#L1428-L1438
- https://github.com/PrismML-Eng/llama.cpp/blob/adfffbe41b2cabcd51fff326ab045662265062bb/ggml/src/ggml-metal/ggml-metal-ops.cpp#L2669-L2706
- As one example of prefill graph shape, `src/models/qwen35.cpp` builds hidden activations of `[n_embd,n_tokens]`, not `[n_embd,1]` for all prefill. Exact model graph/ops must still be traced.

### WRONG: only `ne11==1` vs `>1` is a kernel boundary
For eligible `GGML_TYPE_PTQ1_0` weights and F32 activations, **`2 <= ne11 <= 8`** is a dedicated `mul_mv_ext` dispatch region in `ggml-metal-ops.cpp` lines 2791+, while the conventional `mul_mm` case requires `ne11 > ne11_mm_min` (normally 8 for PTQ1), supported device/layout, and `ne00>=64`. This is a **real candidate route boundary** at 8->9+, *not guaranteed* on every operator or on the M5 until verified.
- https://github.com/PrismML-Eng/llama.cpp/blob/adfffbe41b2cabcd51fff326ab045662265062bb/ggml/src/ggml-metal/ggml-metal-ops.cpp#L2791-L2910
- `GGML_METAL_PTQ1_MULTICOL=1` is a separate **opt-in** `2<=ne11<=4` PTQ1 path; absent the env setting, it is disabled. Do not confuse it with the default small-batch route or matrix-matrix route:
  https://github.com/PrismML-Eng/llama.cpp/blob/adfffbe41b2cabcd51fff326ab045662265062bb/ggml/src/ggml-metal/ggml-metal-device.cpp#L885-L890

### WRONG: report's pseudocode is source-verified pinned Prism
AI B report cited `ggml-metal.m`, `ggml_metal_mul_mat_compute_dispatch()`, `GGML_TYPE_TQ1_0`, a mandatory `ne11%32==0` check, and kernel `kernel_mul_mv_tq1_0_f32` as if describing this branch. Those are **not the matched identifiers/conditions** of pinned `ggml-metal-ops.cpp`. Its asserted “16/16 definitely does not switch” is therefore unsupported.

### UNSUPPORTED: 16/16 adds ~1.5MB, risk <5%
The report's memory approximation assumes an arbitrary hidden size and buffer count and omits Metal graph/command buffering, peak concurrent allocations, model placement, and iPad jetsam. Same is true of `KV ~5GB` based on `n_layers*d_model` without model-specific KV head dimensions and hybrid layers. **Measure peak memory and use actual GGUF/hparams**, do not present made-up risk percentages.

### UNSUPPORTED: 70% confidence Swift-overhead, GPU saturation only 20%, etc.
No profile or accounting supports these percentages. Infer no probabilities. Similarly “4->8 was ineffective” is not strict A/B since Build92 measured ~7300 unfinished tokens while Build93 completed 1192; the available data demonstrates *no dramatic observed gain*, not a statistically controlled performance result.

### INCORRECT/UNSAFE code fragments in AI B proposal
- `n_gpu_layers` belongs to `llama_model_params`, not `llama_context_params`. Current engine uses `llama_init_from_model` (not the pseudocode `llama_new_context_with_model`); existing lifecycle and context-recreation path must be reused, not rewritten blindly.
- `previous crash detected` may indicate kill/OS termination/force quit or incomplete trial; **not** proof 16 caused Jetsam.
- Manual Mac Instruments trace cannot be a blocking P0 step in the user's **Windows + iPad, no-Mac** environment. A bounded native instrumentation hook is preferable; keep `xcrun` CI compilation in GitHub Actions.
- A 256-token input with batch4 vs batch8 is ~64 vs ~32 `llama_decode` calls (assuming no prefix reuse), **not** 298->149 (those counts belong to a ~1192-token example).
- One or two short tests cannot justify “95% confidence” or immediate production-default promotion.

## 3. Freeze Build94 P0 as a minimal proof-oriented experiment

**Single source/build.** No Prism upgrade, no KV precision change, no GPU layer change, no mixed multicol env changes, no 32+/64 batch sweep.

A. **Fix and instrument counters in the existing Build93 observer**, leveraging existing in-memory lock:
- Preserve `native_batch_last_completed_ms` at `decode_begin`.
- At successful `decode_end` increment completed native `llama_decode` count, completed token count, total **host-wall llama_decode** milliseconds; expose average (or bounded histogram), current in-flight elapsed, last completed batch duration, effective `n_batch/n_ubatch`.
- Keep GPU compute time **unknown** unless actually instrumented; `llama_decode` wall time is not labeled GPU compute time. Avoid synchronous per-layer prints or prompt logging. Track failures separately.

B. **Kernel route observation (optional limited Prism patch only if needed):**
- First rely on pinned-source dispatch decision plus measured actual n_batch/ubatch; if still ambiguous, add a bounded, low-overhead *once per unique* (weight type, `ne11` range, operation branch) native counter, exposed in a diagnostic snapshot. Do not printf every matmul or perform per-op filesystem writes. Since adding it touches native backend, build/validate separate from pure Swift observer edit when possible.
- Never claim a specific runtime kernel is proven purely by checking a source `if` condition.

C. **Controlled two-arm 32K A/B:** 8/8 vs guarded 16/16. Require an explicit next-launch arm, no simultaneous activity, fresh context on change, 4/4 recovery state preserved, actual effective shape attested. Separate candidate from production defaults; do not rely on Build93's existing sticky fallback as a generic A/B selector without adapting it. No automatic app relaunch promises. Align short/inference profiles and KV cache reuse.
- Test one identical deterministic `~256 actual tokens` prompt each, record hash, server measured prompt tokens and full prefill time, native batch count/times, nominal thermal, memory/Metal before and after.
- If stable and candidate shows real speedup, optional `~512–650 tokens` same-prompt A/B. Repeat only as needed for variability; exclude KV-cached repeats or use fresh contexts/different prefixes and verified suffix counts.
- Stop at any context-init failure, decoder error, unexpected configuration, client timeout, severe thermal/memory pressure, abnormal exit, or insufficient evidence.
- Verdicts: PASS candidate is viable and materially faster in tested envelope; FAIL failure or clear regression; INCONCLUSIVE partial/uncertain evidence. **No Stable/default promotion until broader evidence.**

D. **Why test 16 before having a GPU trace?**
- There is real pinned-source boundary evidence at 8 and *existing but non-transferable* Build72–74 batch ladder results (614 tokens, 8->16 strong, 16->32 strong, 32->64 weak); one bounded 16/16 short test is cheaper than building a large profiling system.
- Reject AI B's precondition “8 must first show improved performance before testing 16”: the very hypothesis is a discontinuous threshold near 8.
- A direct experiment does not assume improvement or rule out other bottlenecks.

## 4. Device workflow constraints

- iPad Pro M5 12GB; user uses Windows / PowerShell, GitHub Actions, iPad only (no Mac).
- Signed IPA installed by user's established workflow, then a **one-click** Windows driver connects to already running OpenAI-compatible API.
- Drivers must validate `/debug/build`, model, `/debug/execution`, arm/effective context/batch, and memory/thermal before sending expensive requests.
- Never persist API keys, raw prompts, or completions. Archive structured evidence ZIP.
- Hard avoid repeating long 7300-token load; no changes that require user to hand-edit multiple configuration files.

## 5. Release gating

- Preserve Build92 and Build93 references and SHA unchanged.
- Build94 must live on separate branch; tests for state-machine fallback, observer timing, 8/16 effective shape, API regressions, plus real unsigned IPA on macOS CI.
- A CI success is **build-ready**, not a device-performance verdict.
- Candidate 16/16 remains experimental even if it is faster on a single prompt.

**Disposition of AI B report**: accept diagnostic minimalism and conservative gating; reject the invalid `ne11=1` premise, hallucinated pseudo-source, memory “<5% risk”, requirement for Mac, and unjustified statistical claims. Build94 should both **measure** and run a tightly controlled **16/16 candidate**, rather than postponing the test indefinitely.
