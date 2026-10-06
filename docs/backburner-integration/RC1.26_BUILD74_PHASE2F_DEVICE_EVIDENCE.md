# RC1.26 Build 74 — Phase 2F Device Evidence

Captured: 2026-10-06 (+08:00)

## Decision

**CLOSE BATCH LADDER / KEEP 32×32 / DO NOT PROMOTE 64×64**

Controlled 614-token A/B:
- BASELINE32 avg prefill: 11,741.664 ms.
- CANDIDATE64 avg prefill: 10,729.679 ms.
- Prefill improvement: **8.619%**.
- BASELINE32 avg TTFT: 12,503.624 ms.
- CANDIDATE64 avg TTFT: 11,878.803 ms.
- TTFT improvement: **4.997%**.
- Decode-to-first: 761.960 ms -> 1,149.125 ms (**+50.812% slower**).
- Decode throughput: 1.195827 tok/s -> 0.817293 tok/s (**-31.655%**).
- CANDIDATE64 included prefill samples: 10,726.647 / 10,732.710 ms.
- CANDIDATE64 prefill CV: **0.040%**.
- Prompt tokens: 614 in both arms.
- Deterministic answer: `OK`.
- Answer SHA-256: `565339bc4d33d72817b583024112eb7f5cdf3e5eef0252d6ec1b9c9a94e12bb3`.
- Fresh process IDs differed between arms.
- Thermal: nominal -> nominal in both arms.
- Metal allocation delta: +262,144 bytes in both arms.

Memory deltas during measured arm:
- BASELINE32 resident: +4,636,672 bytes.
- CANDIDATE64 resident: +16,973,824 bytes.
- BASELINE32 phys footprint: +31,899,672 bytes.
- CANDIDATE64 phys footprint: +49,152,024 bytes.

Evidence ZIP SHA-256:
- BASELINE32: `726ff7651d9bb42e999222a3e93e6359b124b0e94e818e0dfab5ad28317594d2`
- CANDIDATE64: `ad81980ec7c77ced531561a715add692117bda482fb459c86bd93db144390f47`

## Interpretation

64×64 is technically stable and gives a small additional prefill win, but it crosses the useful knee:
- only 8.619% prefill gain,
- only 4.997% TTFT gain,
- materially worse first-token decode latency,
- materially worse decode throughput,
- somewhat larger resident/footprint growth.

Therefore the batch-size ladder stops here. 128×128 is not justified. 32×32 remains the leading stable candidate for the next stabilization build.
