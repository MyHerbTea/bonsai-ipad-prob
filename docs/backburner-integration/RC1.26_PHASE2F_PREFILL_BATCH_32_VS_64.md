# RC1.26 Phase 2F — Prefill Batch 32 vs 64

Build 73 showed a decisive 48.786% additional prefill improvement from 16/16 to 32/32 with nominal thermal state and no meaningful additional Metal allocation.

Build 74 tests the next step:
- BASELINE32: batch=32, ubatch=32.
- CANDIDATE64: batch=64, ubatch=64.
- Metal Tensor forced disabled in both arms.
- Same 614-token deterministic workload.
- 1 excluded warm-up + 2 included measurements.
- Full app restart between arms.

Gate relative to BASELINE32:
- >=20% additional prefill improvement: strong proceed.
- 10–20%: proceed to confirmation.
- 5–10%: investigate.
- <5%: retain 32/32 as the leading candidate.
- any crash/jetsam/context-create failure, thermal serious/critical, or material memory regression: reject 64/64.

No production promotion is implied by Build 74.
