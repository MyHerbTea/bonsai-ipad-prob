# RC1.26 Phase 2E — Prefill Batch 16 vs 32 Viability

Build 72 Phase 2D returned a 67.29% prefill improvement from batch/ubatch 8/8 to 16/16 on the controlled 614-token workload.

Build 73 tests whether the improvement continues at 32/32 or reaches a memory/thermal/scheduling knee.

## Arms
- BASELINE16: batch=16, ubatch=16.
- CANDIDATE32: batch=32, ubatch=32.
- Metal Tensor remains forced disabled.
- Same model, context, API semantics, generation settings, prompt, seed, and output budget.
- Full app restart required between arms.

## Workload
- 614 prompt tokens expected.
- 1 excluded warm-up.
- 2 included measurements.
- deterministic answer hash required.
- telemetry before/after.
- runtime shape evidence required.

## Gate
Relative to BASELINE16:
- >=20% additional prefill improvement: strong proceed.
- 10–20%: proceed to confirmation.
- 5–10%: investigate.
- <5%: keep 16/16 as the current best candidate.
- any crash, jetsam, context-create failure, thermal serious/critical, or meaningful memory regression: reject 32/32.

This remains experimental; no production promotion is implied by Build 73.


## Build 73 device closure

Device A/B on 2026-10-06 returned a **STRONG PASS**.

- BASELINE16 avg prefill: 23,020.009 ms.
- CANDIDATE32 avg prefill: 11,789.429 ms.
- Prefill improvement: **48.786%** (1.953x).
- TTFT improvement: **47.319%**.
- Decode-to-first improved by 2.964%.
- Decode tok/s improved by 2.813%.
- CANDIDATE32 prefill CV: 0.575%.
- Thermal stayed nominal.
- Metal allocation delta was identical (+256 KiB) in both arms.

Detailed evidence: `RC1.26_BUILD73_PHASE2E_DEVICE_EVIDENCE.md`.

Decision: proceed to Build 74 / Phase 2F (32/32 vs 64/64). Do not yet promote 32/32 to the production default until the next batch-size knee is measured.
