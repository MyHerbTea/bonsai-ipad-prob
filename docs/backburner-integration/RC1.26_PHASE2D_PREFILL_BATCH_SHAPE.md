# RC1.26 Phase 2D — Prefill Batch Shape Viability

## Motivation

Build 71 closed Phase 2C as SAFE_NO_GAIN. Metal Tensor was successfully enabled on Apple M5 but regressed the controlled 1658-token prefill by about 3.56%.

The accepted Build 71 BASELINE evidence exposed a larger structural bottleneck: the OpenAI API runtime hard-codes `batch=8` and `ubatch=8`. Text prefill calls `evalTextTokens(... batchSize: appliedRuntime.batch)`, so a 1658-token prompt requires roughly 208 prefill decode batches before generation.

## Build 72 experiment

Build 72 isolates only API prefill batch shape:

- `BASELINE8`: batch=8, ubatch=8.
- `CANDIDATE16`: batch=16, ubatch=16.
- Metal Tensor is forced back to disabled baseline state in both arms.
- Model, context, OpenAI protocol, generation, Vision, decode path, and production defaults are otherwise unchanged.
- The selected arm is launch-latched. Switching arms requires a full app process restart.

The test runner is packaged in the GitHub Actions artifact:

`tools/rc126_phase2d_prefill_batch_arm.ps1`

## Low-cost viability workload

To avoid repeating the 40-minute Phase 2C device run, Phase 2D uses a shorter deterministic prompt (64 repeated token groups), one excluded warm-up, and two included measurements per arm.

The runner records:

- active batch / ubatch evidence;
- prompt/completion token counts;
- prefill ms;
- decode-to-first-token ms;
- TTFT;
- decode tok/s;
- answer SHA-256;
- telemetry before and after;
- process launch ID.

## Gate

Phase 2D is a viability gate, not a production promotion.

- >=20% prefill improvement with stable memory/thermal behavior: strong proceed.
- 10–20% improvement: proceed to controlled confirmation.
- 5–10% improvement: investigate carefully.
- <5% improvement or any crash/jetsam/context-create regression: no promotion.

A successful 16/16 result may justify a later 32/32 experiment. Build 72 does not test 32/32.


## Build 72 device closure

Device A/B on 2026-10-06 produced a **STRONG PASS**.

- BASELINE8 avg prefill: 85,948.521 ms.
- CANDIDATE16 avg prefill: 28,113.818 ms.
- Prefill improvement: **67.290%** (3.057x speedup).
- TTFT improvement: **66.438%**.
- Decode-to-first regression: 0.410%.
- Decode tok/s regression: 0.808%.
- Thermal remained nominal in both arms.
- Metal allocation delta was identical (+256 KiB) in both arms.
- Prompt tokens and answer hash were identical.

CANDIDATE16 had higher sample variance, but even its slower included sample remained more than 62% faster than the fastest BASELINE8 sample. The improvement is therefore decisive.

Detailed evidence: `RC1.26_BUILD72_PHASE2D_DEVICE_EVIDENCE.md`.

Decision: proceed to Build 73 / Phase 2E (16/16 vs 32/32). Do not yet promote 16/16 to the production default until the next batch-size knee and confirmation behavior are known.
