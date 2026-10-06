# RC1.26 Build 71 — Phase 2C-1 Fresh-Backend Metal Tensor Device Evidence

Captured on device: 2026-10-06 (+08:00).

## Decision

**PASS_MECHANISM / FAIL_PERFORMANCE_GATE / CLOSE_PHASE2C_NO_PROMOTION**

Build 71 successfully proved that the pinned Prism backend can be started in two distinct fresh-process states on the Apple M5 device:

- BASELINE: `GGML_METAL_TENSOR_DISABLE=1`, backend log `has tensor = false`.
- CANDIDATE: `GGML_METAL_TENSOR_DISABLE` unset, backend log `has tensor = true`.
- The two arms used different process launch IDs.
- Runtime arm switching remained forbidden and restart-required.
- Graph-level Tensor-kernel dispatch remains explicitly unproven.

The mechanism therefore works as designed. The candidate, however, failed the prefill/TTFT promotion gate.

## Provenance

- Build ID: `rc1.26-build71-fresh-backend-metal-tensor-ab`
- Build: `71`
- Build 71 CI source: `77f6ee43d000883bd3f0ce08dbcb5ff53296ff7d`
- Frozen baseline: RC1.25.3 Build 64, `0d84e106daa10590ddbd1b7a3b6b3212114db6f7`
- Prism release: `prism-b10743-adfffbe`
- Prism source: `adfffbe41b2cabcd51fff326ab045662265062bb`
- Prism XCFramework SHA-256: `d23bb0325cca43054c1a76a233c79950a1ce26d98a359466c8d81fafd3b1d9ad`

Evidence ZIP SHA-256:
- BASELINE: `3fac9e2ff75d0da389222aa9d16fb1db85e0601c5c50fd843a609edc008c55b5`
- CANDIDATE: `1f2f45e9b0532ffe7fc0ac43c8df2e467fe2861527f24c5877954fd331f75fef`

## Controlled workload

Both arms used the same deterministic request:

- prompt tokens: 1658
- completion tokens: 1
- answer: `OK`
- answer SHA-256: `565339bc4d33d72817b583024112eb7f5cdf3e5eef0252d6ec1b9c9a94e12bb3`
- one excluded warm-up
- three included measurements
- identical prompt, seed, output budget, model, API path, and Build 71 binary

## Measurements

| Metric | BASELINE | CANDIDATE | Candidate change |
|---|---:|---:|---:|
| Avg prefill | 254,616.111 ms | 263,672.050 ms | **+3.557% slower** |
| Avg TTFT | 255,195.273 ms | 264,247.221 ms | **+3.547% slower** |
| Avg decode-to-first | 579.162 ms | 575.171 ms | 0.689% faster |
| Avg decode tok/s | 1.45495 | 1.46181 | 0.472% faster |

Included prefill samples:

- BASELINE: 249,324.368 / 253,004.486 / 261,519.479 ms
- CANDIDATE: 263,542.692 / 264,212.552 / 263,260.906 ms

Prefill coefficient of variation:

- BASELINE: 2.457%
- CANDIDATE: 0.185%

The candidate's three included samples are tightly clustered, so the observed lack of gain is not explained by candidate-side timing noise.

## Thermal and memory observations

BASELINE telemetry:
- thermal: nominal -> nominal
- Metal allocated delta: +262,144 bytes
- Metal headroom delta: -262,144 bytes
- resident delta: -13,598,720 bytes
- physical footprint delta: +44,171,264 bytes

CANDIDATE telemetry:
- thermal: nominal -> fair
- Metal allocated delta: +262,144 bytes
- Metal headroom delta: -262,144 bytes
- resident delta: +10,600,448 bytes
- physical footprint delta: +27,901,952 bytes

There is no meaningful Metal-memory advantage: both arms changed Metal allocation/headroom by the same 256 KiB. Process-memory deltas are mixed and do not justify promotion. The candidate ended at thermal state `fair` while baseline remained `nominal`; a single run is not sufficient to assign causality, but it provides no reason to continue a performance candidate that is already slower.

## Gate decision

The established Phase 2C promotion rule was:

- >=5% clear prefill win: proceed
- 3–5% win: hold/investigate
- <3% win: noise absent meaningful memory benefit
- decode regression <=2%

Build 71 CANDIDATE did not produce a win. It produced a ~3.56% prefill regression and ~3.55% TTFT regression. The ~0.69% decode-to-first improvement and ~0.47% tok/s improvement are too small to offset the prefill loss.

Therefore:

1. Do not proceed to Phase 2C-2 ABABAB.
2. Do not run the Phase 2C context ladder.
3. Do not promote Metal Tensor into ACCELERATED or production defaults.
4. Preserve Build 71 as experimental evidence only.
5. Keep the frozen Build 64 behavior as the production-equivalent baseline.
6. The Build 71 CANDIDATE script scheduled BASELINE for the next process launch; restart the app before normal continued use.

Phase 2C is closed as **NO PROMOTION / SAFE_NO_GAIN**.
