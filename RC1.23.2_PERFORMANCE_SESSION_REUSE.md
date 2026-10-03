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
