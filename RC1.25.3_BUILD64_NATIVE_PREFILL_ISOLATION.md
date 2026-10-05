# RC1.25.3 Build 64 — Native Prefill Isolation

## Trigger

RC1.25.2 Build 63 repeated the Build 62 failure on-device:

- 1-image API vision: PASS
- 2-image API vision: PASS
- 3-image API vision: PASS
- immediate single-image visual follow-up: connection reset / app process loss

The persisted post-crash health snapshot narrowed the failure boundary to:

- last MLX stage: `MLX_INJECT_03_PACKET_READY`
- vision request stage: `native_prefill_begin`
- last API image count: 1
- last multi-image layout: `single`

Therefore the failing request completed MLX vision encoding and projected-packet creation, then terminated after entering native cached-vision prefill.

## Build 64 hypothesis

The API had historically allowed the experimental vision prefix-KV checkpoint to remain enabled across requests. Earlier device certification intentionally enabled this optimization and AppStorage preserves the setting.

For Build 64, external OpenAI-compatible vision requests are isolated from this optimization:

1. before every API vision encode, explicitly clear the independent native prefix-KV snapshot;
2. clear the Swift-side prefix-reuse key/position metadata;
3. clear live llama working KV;
4. run MLX encode;
5. enter cached-vision native prefill with `reuse_prefix = 0`;
6. do not create a new prefix snapshot for the next API request;
7. keep the mmap 27B model and llama_context resident.

This is an isolation/stability change, not a claim that prefix snapshot reuse is proven to be the root cause.

## Native stage instrumentation

Build 64 persists the following additional two-phase stages:

- `TWOPHASE_B00_ENTER`
- `TWOPHASE_B01_CACHE_LOADED`
- `TWOPHASE_B02_ADMISSION_PASS`
- `TWOPHASE_B03_PREFIX_REUSE_CHECK`
- `TWOPHASE_B03_PREFIX_REUSE_MISS`
- `TWOPHASE_B03_PREFIX_STATE_CLEARED`
- `TWOPHASE_B10_PREFIX_TEXT_BEGIN`
- `TWOPHASE_B11_PREFIX_TEXT_DONE`
- `TWOPHASE_B20_IMAGE_EMBED_BEGIN`
- `TWOPHASE_B21_IMAGE_EMBED_DONE`
- `TWOPHASE_B22_PREFIX_SNAPSHOT_SAVE_BEGIN`
- `TWOPHASE_B30_SUFFIX_TEXT_BEGIN`
- `TWOPHASE_B31_SUFFIX_TEXT_DONE`
- existing `TWOPHASE_B99_PREFILL_READY`

`/health` now exposes:

- `last_two_phase_vision_stage`
- `configured_vision_prefix_kv_reuse_enabled`
- `api_vision_prefix_reuse_effective`

The configured UI toggle may remain true from older experiments, while the Build 64 external API path must report `api_vision_prefix_reuse_effective=false`.

## Acceptance gate

Use the same failure sequence as Build 63 at Context Window 2048 / ACCELERATED:

1. 1 image
2. 2 images
3. 3 images
4. immediate single-image visual follow-up
5. post-vision text survival
6. repeat the 3-image -> follow-up -> text boundary at least twice

A product PASS requires no app restart and no API process loss.

If the process still terminates, the persisted `last_two_phase_vision_stage` must localize the failure to prefix text decode, image embedding decode, snapshot handling, or suffix text decode before any further architectural change.
