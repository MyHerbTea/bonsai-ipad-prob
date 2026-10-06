# RC1.26 Build 72 — Phase 2D Prefill Batch Shape Device Evidence

Captured on device: 2026-10-06 (+08:00).

## Decision

**STRONG PASS / PROCEED TO 16 VS 32**

Build 72 isolated only the OpenAI API text prefill batch shape while keeping Metal Tensor disabled.

- BASELINE8: batch=8, ubatch=8.
- CANDIDATE16: batch=16, ubatch=16.
- Prompt tokens: 614.
- Completion tokens: 1.
- Deterministic answer: `OK`.
- Answer SHA-256: `565339bc4d33d72817b583024112eb7f5cdf3e5eef0252d6ec1b9c9a94e12bb3`.
- Fresh process launch IDs differed between arms.
- Thermal state remained `nominal` before and after both arms.
- Metal allocation delta was +262,144 bytes in both arms.

Evidence ZIP SHA-256:
- BASELINE8: `12af07c9262b5b7905b2279de760084a760dcca067f00c24b496da6a86077e17`
- CANDIDATE16: `1303027b08c3a8fe5144ac437886e542f4463a1f887d197d62ab5bc3f8e08679`

## Measurements

| Metric | BASELINE8 | CANDIDATE16 | Candidate change |
|---|---:|---:|---:|
| Avg prefill | 85,948.521 ms | 28,113.818 ms | **67.290% faster** |
| Avg TTFT | 87,043.328 ms | 29,213.112 ms | **66.438% faster** |
| Avg decode-to-first | 1,094.808 ms | 1,099.294 ms | 0.410% slower |
| Avg decode tok/s | 0.83516 | 0.82842 | 0.808% slower |

Included prefill samples:
- BASELINE8: 84,455.169 / 87,441.873 ms.
- CANDIDATE16: 24,520.224 / 31,707.412 ms.

Prefill coefficient of variation:
- BASELINE8: 2.457%.
- CANDIDATE16: 18.077%.

Although CANDIDATE16 variance is higher, even its slower included sample (31.707 s) is more than 62% faster than the fastest BASELINE8 sample (84.455 s). The direction and magnitude are therefore unambiguous.

## Resource observations

BASELINE8:
- thermal: nominal -> nominal
- Metal allocated delta: +262,144 bytes
- resident delta: +15,024,128 bytes
- physical footprint delta: +47,251,456 bytes

CANDIDATE16:
- thermal: nominal -> nominal
- Metal allocated delta: +262,144 bytes
- resident delta: +15,646,720 bytes
- physical footprint delta: +47,792,128 bytes

No meaningful additional Metal-memory cost was observed for 16/16 in this workload.

## Gate

Build 72 exceeded the Phase 2D strong-proceed threshold (>=20%) by a wide margin. It is not yet promoted to the production default because:
1. only two included measurements per arm were used;
2. CANDIDATE16 variance was elevated;
3. the next batch-size knee is unknown.

Proceed to Build 73 / Phase 2E: BASELINE16 vs CANDIDATE32 with the same deterministic workload and safety isolation.
