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


## Build 74 device closure

Device A/B returned **KEEP 32×32 / REJECT 64×64 AS DEFAULT**.

- Prefill: 11,741.664 ms -> 10,729.679 ms (**8.619% faster**).
- TTFT: 12,503.624 ms -> 11,878.803 ms (**4.997% faster**).
- Decode-to-first: **50.812% slower** at 64×64.
- Decode throughput: **31.655% lower** at 64×64.
- Thermal remained nominal.
- Metal allocation delta stayed +256 KiB.
- 64×64 was stable (prefill CV 0.040%), so the rejection is a quality/performance tradeoff decision, not a correctness failure.

Decision: stop the batch ladder. Do not test 128×128. Carry 32×32 into the next stabilization build.

Detailed evidence: `RC1.26_BUILD74_PHASE2F_DEVICE_EVIDENCE.md`.
