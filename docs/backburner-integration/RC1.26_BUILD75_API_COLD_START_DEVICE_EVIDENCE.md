# RC1.26 Build 75 — API Cold-Start Device Evidence

Captured: 2026-10-06 18:35 +08:00

## Verdict

**PASS — FIRST API COLD START COMPLETED WITHOUT RESTART**

The Build 75 cold-start guard passed on the first API startup attempt after installation.

Observed device evidence:
- build_id: `rc1.26-build75-api-cold-start-guard`
- build: `75`
- health: `ok`
- context_window: `2048`
- startup_stage: `READY`
- startup_previous_incomplete: `none`
- startup_attempt: `1`
- startup_last_error: `none`
- last_engine_stage: `MODEL_09_READY`
- launch arm: `BASELINE32`
- next launch arm: `BASELINE32`
- active batch/uBatch: `32/32`
- shape_evidence_valid: `true`
- Metal Tensor forced baseline: `true`
- GGML_METAL_TENSOR_DISABLE: `1`
- process_launch_id: `3409BD1B-A32E-4F65-91EF-7ED5C03EDC9E`

Evidence ZIP:
- `rc126-build75-cold-start-20261006-183524.zip`
- SHA-256: `3ad874a8d1a05c8ef0e4c57eb0b23b41428f4875d31be632111ef14f16e7d0e4`

## Interpretation

Build 74 exhibited a first-start failure mode where the first model/API setup could terminate the app and the second attempt succeeded. Build 75's staged startup path completed on attempt 1 with no previous incomplete state and no recorded startup error.

This is sufficient to close the specific Build 74 first-start regression for the tested install path. It is not a statistical guarantee across all install histories, but it is a successful targeted reproduction test of the exact failure mode that motivated Build 75.

32×32 remains the selected runtime batch shape. No 64×64 or 128×128 promotion is made.
