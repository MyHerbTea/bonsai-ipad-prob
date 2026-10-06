# RC1.26 Build 73 — Phase 2E Device Evidence

Captured: 2026-10-06 (+08:00)

## Decision

**STRONG PASS / PROCEED TO 32 VS 64**

Controlled 614-token A/B:
- BASELINE16 avg prefill: 23,020.009 ms.
- CANDIDATE32 avg prefill: 11,789.429 ms.
- Prefill improvement: **48.786%** (**1.953x**).
- TTFT improvement: **47.319%**.
- Decode-to-first improved by **2.964%**.
- Decode tok/s improved by **2.813%**.
- CANDIDATE32 included prefill samples: 11,837.402 / 11,741.457 ms.
- CANDIDATE32 prefill CV: **0.575%**.
- Prompt tokens: 614 in both arms.
- Deterministic answer: `OK`.
- Answer SHA-256: `565339bc4d33d72817b583024112eb7f5cdf3e5eef0252d6ec1b9c9a94e12bb3`.
- Fresh process IDs differed between arms.
- Thermal: nominal -> nominal in both arms.
- Metal allocation delta: +262,144 bytes in both arms.

Evidence ZIP SHA-256:
- BASELINE16: `4ff643f268b57fab24d4472d847d2b0d237144728e5f41dd41de9c190bc3bad0`
- CANDIDATE32: `316b33c4de8906c3846752590c424a161605181db04d330028bf9689a828ed22`

No meaningful memory/thermal penalty was observed. 32/32 is not yet promoted as the final production default because the next batch-size knee is unknown.

Proceed to Build 74 / Phase 2F: BASELINE32 vs CANDIDATE64.
