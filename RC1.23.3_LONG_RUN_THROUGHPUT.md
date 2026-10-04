# RC1.23.3 — Long-Run Throughput Observability

Status: **ACTIVE DEVELOPMENT — PHASE A2 THERMAL / IDLE-GAP CORRELATION**

Parent frozen baseline:

- RC1.23.2 build 41;
- frozen documentation commit: `15d87374df906e9687badbc6d2527a12a7086ddf`;
- executable source baseline: `990e8d6d90a660461fa14c4d391202efb2eb0bd5`;
- accepted C2-B architecture: single-sequence ON_DEVICE prefix-state checkpoint.

RC1.23.2 is immutable. RC1.23.3 work occurs only on
`lab-v1-rc1-23-3-production-hardening`.

## Frozen boundaries

RC1.23.3 must not change `n_seq_max=1`, C2-B state save/restore, Prism
ON_DEVICE checkpoint flags, reuse identity, invalidation semantics, BVCACHE1,
projection width 5120, RC1.22.5 hard graph-cut, or RC1.23.1 API/error behavior.
C1 partial trimming and C2-A multi-sequence checkpointing remain rejected.

## Phase A1 — build 42 result

A real iPad Pro M5 / iPadOS 27.0.1 run completed one seed request plus twenty
same-image warm requests successfully.

- ordinals 2–21 remained C2-B HIT with retained=true;
- warm HIT prefix/image prefill stayed at 0;
- fastest warm requests were about 17.6–17.9 s;
- slower requests reached about 24–27 s;
- decode throughput fell from about 8.6 tok/s to about 6.1 tok/s;
- suffix prefill rose from roughly 2.4–2.6 s to roughly 3.4–3.6 s;
- ordinals 13–14 recovered strongly to about 8.6 tok/s before degrading again;
- process/Metal resource counters showed no monotonic leak pattern;
- Metal allocation stayed approximately 5771–5772 MiB.

Classification: checkpoint stability PASS; functional stability PASS;
monotonic memory accumulation NOT DETECTED; dominant slowdown component 27B
decode; secondary correlated component suffix prefill; thermal/DVFS is the
leading high-confidence hypothesis but is not yet proven.

## Phase A2 — build 43 objective

Build 43 adds per-request environment correlation without changing inference:

- `idle_gap_ms` since the prior completed request;
- session elapsed time at request start/end;
- `ProcessInfo.processInfo.thermalState` at request start/end;
- Low Power Mode at request start/end;
- all build-42 throughput and resource fields remain.

The rolling history remains bounded to the most recent 32 requests.

## A2 decision rule

Promote thermal/DVFS from hypothesis to device-evidence-confirmed only when
target-device data shows throughput degradation/recovery correlated with thermal
state and/or a controlled cool-down gap, without corresponding monotonic
process/Metal resource growth. If thermal state remains unchanged while
throughput repeatedly degrades and recovers, continue into runtime/scheduler
instrumentation instead of changing C2-B.

## Privacy boundary

Diagnostics must not record API keys, raw images, base64 payloads, prompt text,
or assistant output.

## Build 43 acceptance gate

1. Frozen RC1.23.2 contracts pass.
2. Build 43 compiles/packages.
3. C2-B behavior is unchanged.
4. A2 fields appear in last-request metrics and rolling history.
5. Controlled warm-load → cool-down → warm-load data is interpretable from the
   app telemetry itself.
6. No thermal conclusion is claimed before true-device A2 evidence.

## Phase B — build 44 runtime-profile A/B

Build 43 A2 device evidence established a reversible, cooldown-sensitive
performance loss: after a ~45.3 s idle gap, decode recovered from roughly
6.08 tok/s to 8.57 tok/s with no meaningful memory or Metal allocation change.
The public iPadOS thermal state remained nominal, so the exact underlying
mechanism (DVFS, GPU power state, scheduler, or another device-level policy)
is not exposed by that coarse signal.

Build 44 therefore stops adding observability and starts controlled performance
optimization. The current safe runtime remains the default and two opt-in
profiles are added:

- `safe`: Flash Attention OFF, KQV OFF, Op Offload OFF;
- `flash`: Flash Attention ON, KQV OFF, Op Offload OFF;
- `accelerated`: Flash Attention ON, KQV ON, Op Offload ON.

Changing profile is disabled while the API server is running and requires an
API restart, ensuring each run uses one immutable context configuration.
C2-B checkpoint identity/save/restore and `n_seq_max=1` are unchanged.
