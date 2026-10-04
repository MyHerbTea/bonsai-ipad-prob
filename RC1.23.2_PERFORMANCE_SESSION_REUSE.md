# RC1.23.2 — Multimodal Performance & Session Reuse

Status: **ACTIVE DEVELOPMENT — DEVICE CERTIFICATION DEFERRED**

Base: `a032634d992f3b2edf0b3665e9b381ee4d6c06cf`  
Parent behavior: RC1.23.1 OpenAI Multimodal API candidate.

## Goal

Reduce end-to-end latency for repeated local API requests without changing the
validated multimodal semantics.

The optimization order is deliberately:

1. observe,
2. prove a bottleneck,
3. optimize one boundary,
4. compare,
5. keep or revert.

No performance gain may be claimed from CI alone.

## Frozen boundaries

RC1.23.2 must not change:

- RC1.22.5 MLX Vision hard graph-cut execution;
- per-layer safetensors reopen;
- CPU copy/rebuild graph cut;
- projected embedding dimension `5120`;
- BVCACHE1 binary format or native vision injection math;
- RC1.23.1 single-image request/error semantics;
- text API response envelopes or SSE contract;
- explicit failure instead of silent text fallback.

## Phase A — Performance observability

**Implemented first. No inference behavior change.**

Each API request stores one compact last-request snapshot:

- request id;
- route: text / vision;
- streaming flag;
- success or failed/interrupted;
- total request milliseconds;
- image temp-file write milliseconds;
- MLX vision encode milliseconds;
- sidecar-reported encode milliseconds;
- projected-cache write milliseconds;
- 27B vision prefill milliseconds;
- text TTFT milliseconds;
- decode milliseconds;
- tokens/second;
- prompt/completion token counts;
- visual rows;
- projection dimension;
- grid;
- M-RoPE `n_pos`;
- image ordering;
- cache reuse state;
- last stage on failure.

The same data is surfaced through:

`高级与诊断 → 刷新并复制完整诊断 → [LAST API REQUEST PERFORMANCE]`

The diagnostic snapshot remains privacy bounded: no API key, raw image,
base64, prompt body, or assistant response body.

## Phase B — Vision embedding cache reuse

Not enabled in the Phase A baseline.

Candidate design:

- compute the existing content-addressed BVCACHE1 identity before MLX encode;
- validate an existing cache using the frozen native cache validator;
- on a valid hit, skip MLX Vision encode and projected-cache rewrite;
- preserve all RC1.23.1 request/error semantics;
- record `cache_reuse=hit|miss`;
- fall back to the existing RC1.23.1 path on a miss.

This phase requires real-device A/B evidence before being accepted.

## Phase C — 27B context / KV reuse

Not enabled until Phase B is measured.

Any reuse must prove:

- no cross-request prompt leakage;
- no historical-image leakage;
- exact system/user boundary correctness;
- cleanup after failures;
- text API recovery;
- bounded memory growth;
- same response semantics as the frozen baseline.

A warm-path optimization is rejected if it relies on hidden stale KV state.

## CI gate

Every candidate must pass:

- inherited RC1.20.x / RC1.21.x / RC1.22.5 invariants;
- RC1.23.1 multimodal parser/source contracts;
- RC1.23.2 observability source contracts;
- Swift syntax preflight;
- Xcode project generation;
- full Release iOS build;
- Prism multimodal symbol verification;
- unsigned IPA packaging.

## Deferred real-device gate

Because the test iPad is temporarily unavailable, RC1.23.2 may progress through
CI-safe implementation, but may not be frozen or described as faster until a
real-device controlled A/B run is completed.

The first device run should copy one Diagnostic Snapshot after:

1. cold text request;
2. repeated text request;
3. cold image request;
4. same-image repeated request;
5. different-image request;
6. invalid-image failure;
7. post-failure text request.

That single snapshot set will determine whether Phase B or Phase C is the next
optimization target.


## Phase A real-device evidence — 2026-10-04

Device: iPad Pro M5 class, 12 GB, iPadOS 27.0.1.  
Build: 38 observability candidate.

Last successful vision request:

- total internal request: 12099.239 ms;
- MLX vision encode: 241.599 ms;
- sidecar-reported encode: 219.156 ms;
- BVCACHE1 write: 1.803 ms;
- 27B prefill: 9629.370 ms;
- decode: 2220.502 ms;
- decode rate: 8.557 tok/s;
- prompt tokens: 86;
- completion tokens: 19;
- visual rows: 54 x 5120;
- grid: 9x6;
- M-RoPE n_pos: 9.

Windows end-to-end measurements:

- text first: 4322.9 ms;
- text repeat: 4422.4 ms;
- first image: 12761.0 ms;
- same-image repeat: 18415.1 ms;
- post-failure text recovery: 3873.8 ms;
- final vision: 12248.1 ms.

Safety/semantics remained intact:

- stale historical image binding -> HTTP 400 invalid_content_part;
- invalid base64 -> HTTP 400 invalid_image_data;
- text request after failure -> HTTP 200;
- image-grounded output remained correct.

### Decision

Do **not** prioritize projected-embedding cache reuse as the main optimization.
The measured MLX encode + cache write cost is only about 0.24 s, while the
27B multimodal prefill alone is about 9.63 s.

The next optimization target is therefore **Vision-prefix KV reuse**.

## Phase C1 — Experimental Vision-prefix KV reuse

Status: **IMPLEMENTED AS DEFAULT-OFF CANDIDATE; DEVICE A/B REQUIRED**

Design:

- same image is identified by the existing content-addressed BVCACHE1 path;
- same system prompt is part of the reuse identity;
- after a successful request, keep only the KV corresponding to
  `prefix + image`;
- remove the request-specific suffix and generated continuation;
- on the next matching request, decode only the new question suffix;
- any text request, model unload, or request failure invalidates the reuse state;
- if partial KV removal is unsupported, clear the entire llama memory and
  automatically fall back to the RC1.23.1 path;
- BVCACHE1 format, Vision Tower math, projected embedding width and API
  semantics remain unchanged.

The experiment is controlled by:

`高级与诊断 -> 实验：Vision Prefix KV Reuse`

Default: **OFF**.

Diagnostics include:

- prefix_reuse_enabled;
- prefix_reuse_hit;
- prefix_retained;
- prefix_positions;
- prefix_text_ms;
- image_prefill_ms;
- suffix_prefill_ms.

Acceptance requires a controlled OFF/ON real-device A/B using the same image,
question lengths and output budget. The candidate is rejected if it causes
cross-request leakage, historical-image leakage, cleanup failure, memory
growth, or semantic regression.
