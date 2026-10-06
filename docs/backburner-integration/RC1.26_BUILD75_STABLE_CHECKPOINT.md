# RC1.26 Build 75 — Stable Checkpoint

Status: **STABLE CHECKPOINT / DEVICE-CERTIFIED**

## Certified binary identity

The device-certified Build 75 binary is tied to product/CI commit:

`c09b2e09706dd0c0391b7a15727da57e0f17d425`

GitHub Actions:
- Run: `#366`
- Run ID: `37449639193`
- Result: `SUCCESS`
- Artifact ID: `11406281224`
- Artifact name: `BonsaiLab-iPad-v1-RC1.26-Build75-API-Cold-Start-Guard`
- Artifact digest: `sha256:7801bf7bcaffbdfeae0c9bce3b2b679e8859ee5764880af33f971b25df7e1440`

Do not substitute later docs-only commits for this certified binary identity.

## Device certification

Target device:
- iPad Pro M5, 12 GB
- iPadOS 27
- model: Ternary-Bonsai-2-27B-PTQ1_0.gguf
- context: 2048

Cold-start device evidence:
- startup stage: `READY`
- previous incomplete stage: `none`
- startup attempt: `1`
- startup last error: `none`
- health: `ok`
- active batch/uBatch: `32/32`
- shape evidence valid: `true`
- Metal Tensor: disabled

Device evidence ZIP:
- `rc126-build75-cold-start-20261006-183524.zip`
- SHA-256: `3ad874a8d1a05c8ef0e4c57eb0b23b41428f4875d31be632111ef14f16e7d0e4`

Evidence was archived by docs-only commit:

`8c3ff5b3141b8c53ecc58961d489b90622a48ea1`

## Performance checkpoint

Batch ladder:
- 8→16: strong pass
- 16→32: strong pass
- 32→64: stop
- 128: not tested

Selected runtime shape: **32/32**.

Build 74 same-build A/B:
- 32/32 prefill: 11,741.664 ms
- 64/64 prefill: 10,729.679 ms
- 64/64 prefill gain: 8.619%
- 64/64 decode-to-first regression: 50.812%
- 64/64 decode throughput regression: 31.655%

Decision: 32/32 is the stable performance checkpoint.

## Frozen boundaries for the next stage

The next stage must preserve:
1. Build 75 first-start API stability.
2. 32/32 runtime shape unless a controlled A/B explicitly overrides it.
3. Metal Tensor disabled.
4. Existing Vision behavior.
5. OpenAI-compatible API semantics.
6. 2048-context certified path.
7. Existing deterministic workload and telemetry.
8. Build 64 frozen baseline remains immutable.

Any native/product change after this checkpoint requires a new build number.
Runner/docs-only changes do not.

## Next stage

Start a source-and-telemetry audit of the remaining latency after the batch-size knee:
- decode-to-first latency,
- token-by-token decode,
- sampling overhead,
- repeated tokenization/string conversion,
- per-token synchronization or diagnostics,
- unnecessary context/KV lifecycle work,
- residual prefill call fragmentation.

Do not begin by changing more knobs. First identify the dominant measured cost and design one isolated A/B.
