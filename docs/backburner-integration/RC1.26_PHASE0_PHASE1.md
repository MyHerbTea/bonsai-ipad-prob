# RC1.26 Phase 0 + Phase 1 Checkpoint

## Baseline
- Frozen source: `0d84e106daa10590ddbd1b7a3b6b3212114db6f7`
- Frozen branch: `frozen-v1-rc1-25-3-build64-device-certified`
- Final device certification: `20261005-212210`
- Result: PASS, crash=false, recovery=0, release freeze gate=PASS.

## Phase 0
The machine-readable baseline is `BASELINE_MANIFEST.json`. Unknown model/vision SHA256 values are intentionally not invented; the next device manifest must capture them.

## Phase 1 invariant
Phase 1 is observability-only:
- extended process/Metal telemetry;
- runtime profile and feature-flag value types;
- benchmark provenance types;
- no behavior-changing optimization enabled;
- no changes to Vision sidecar, native-prefill lifecycle, OpenAI protocol behavior, generation, context admission, SSE/chunked semantics, or image limits.

## Promotion rule
`BASELINE` remains equivalent to Build 64. Experimental features may only become effective after explicit automated quality, stability, memory, thermal, API, and Vision gates.
