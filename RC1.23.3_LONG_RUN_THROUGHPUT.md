# RC1.23.3 — Long-Run Throughput Observability

Status: **ACTIVE DEVELOPMENT — PHASE A OBSERVABILITY ONLY**

Parent frozen baseline:

- RC1.23.2 build 41;
- frozen branch: `lab-v1-rc1-23-2-performance-session-reuse`;
- frozen documentation commit:
  `15d87374df906e9687badbc6d2527a12a7086ddf`;
- executable source baseline:
  `990e8d6d90a660461fa14c4d391202efb2eb0bd5`;
- accepted C2-B architecture: single-sequence ON_DEVICE prefix-state checkpoint.

RC1.23.2 is immutable. RC1.23.3 work occurs only on
`lab-v1-rc1-23-3-production-hardening`.

## Phase A objective

Explain the long-run throughput degradation observed during the frozen
10-request warm-hit soak without changing C2-B checkpoint semantics.

Observed frozen-baseline behavior:

- early warm-hit end-to-end latency: about 18 s;
- later soak latency: about 24–26 s;
- checkpoint remained HIT and retained=true;
- prefix and image prefill remained 0.000 s;
- MLX peak remained 144 MiB;
- no crash occurred;
- a later same-session probe returned to about 18 s.

The first RC1.23.3 question is therefore:

> Is the later-soak slowdown primarily device/thermal throttling, llama runtime
> long-session degradation, or measurable resource accumulation?

No root cause is assumed in advance.

## Frozen boundaries

Phase A must not change:

- `n_seq_max=1`;
- C2-B state save/restore implementation;
- Prism ON_DEVICE checkpoint flags;
- image/system reuse identity;
- text/failure/unload invalidation;
- BVCACHE1;
- projected width 5120;
- RC1.22.5 MLX hard graph-cut;
- RC1.23.1 API/error semantics;
- the default-OFF state of the reuse toggle.

C1 partial trimming and C2-A multi-sequence checkpointing remain rejected.

## Required observability

The intended build-42 instrumentation should make a repeated-request sequence
easy to analyze without changing inference behavior. At minimum, capture for
each API request:

- monotonically increasing request ordinal;
- route and HIT/MISS state;
- prefix retention state;
- total request milliseconds;
- prefill milliseconds;
- prefix/image/suffix prefill milliseconds;
- decode milliseconds;
- tokens per second;
- Vision encode milliseconds;
- available memory;
- process physical footprint;
- Metal allocated/recommended memory where available.

Metrics must remain privacy bounded and must not record raw images, base64,
prompt text, assistant text, or API keys.

## Phase A acceptance gate

Phase A is accepted only if:

1. the frozen RC1.23.2 contracts still pass;
2. build 42 starts and serves the same requests as build 41;
3. the additional metrics are observational only;
4. a repeated-hit device run can distinguish whether slowdown correlates with
   decode throughput, prefill, or resource growth;
5. no conclusion about thermal/runtime/memory cause is claimed without
   target-device evidence.

## Current transaction

Build 42 is the RC1.23.3 starting build. This initial transaction changes only:

- development branch/version identity;
- build number;
- CI/artifact labeling;
- this phase control document.

It does **not** implement the new runtime metrics yet and does not modify C2-B.
