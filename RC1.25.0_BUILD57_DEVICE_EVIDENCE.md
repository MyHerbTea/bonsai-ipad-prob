# RC1.25.0 Build 57 — Device Certification Evidence

Status: **DEVICE CERTIFIED — FROZEN**

## Identity

- Product version: 1.0.0
- Build: 57
- Certified source commit: `00f854f28e49153dc547b5f32183db82c5910235`
- Source branch: `lab-v1-rc1-25-0-multi-image-openai-api`
- Frozen branch: `frozen-v1-rc1-25-0-build57-multi-image-device-certified`
- CI run: GitHub Actions #64 / run id 37242509681 — PASS
- Artifact: `BonsaiLab-iPad-v1-RC1.25.0-Build57-Multi-Image-OpenAI-API`
- Artifact digest: `sha256:bcf16beab85862a629859e3891f87570430661bdceaee5799a3d9d80123c049e`
- IPA SHA-256: `0c6439c16b7fb8f75be00d85a76a80e2f47854a0f0498c553639931ae57bab13`

## Device baseline

- iPadOS 27.0.1
- physical memory: 11524 MiB
- model: `Ternary-Bonsai-2-27B-PTQ1_0.gguf`
- vision tower: `Bonsai-2-27B-vision_tower-fp16.safetensors`
- API context: 512
- batch / ubatch: 8 / 8
- runtime profile: Full / Accelerated
- Flash Attention: ON
- KQV Offload: ON
- Op Offload: ON
- unified KV: ON
- mmap: ON
- vision prefix KV reuse: ON

## Multi-image implementation

RC1.25.0 extends the local OpenAI-compatible chat completions endpoint from
single-image requests to bounded **1–3 image** requests.

The frozen native BVCACHE1 bridge remains unchanged.

- 1 image: existing single-image path.
- 2 images: ordered left/right contact sheet.
- 3 images: ordered left/center/right contact sheet.
- Contact sheet: bounded 1024x512 JPEG before the existing MLX Vision Tower.
- Maximum images per request: 3.
- Remote image URLs remain unsupported.

This is a compatibility adapter, not native independent multi-image vision-token blocks.

## Three-image device validation

Three-image request used:

1. `vision_test_01_people_landscape.png`
2. `vision_test_02_menu_ocr.png`
3. `vision_test_03_complex_scene.png`

The compact semantic probe passed:

- prompt tokens: 227
- completion tokens: 115
- finish reason: stop
- Image 1 label present: YES
- Image 2 label present: YES
- Image 3 label present: YES
- Compare label present: YES

Observed semantic separation:

- Image 1: woman + golden retriever + lake/mountain scene
- Image 2: menu/OCR content
- Image 3: green vintage tram + cherry blossoms + pedestrians

No obvious image-order swap or cross-image scene merge was observed.

The runtime reported:

- source contact sheet: 1024x512
- resized vision input: 352x160
- vision output: 55 x 5120
- ordering: multiple
- layout: left-center-right
- prefix reuse path: functional
- final stage: `TWOPHASE_VISION_99_PASS`

## Final six-case certification

**Result: PASS 6/6**

### 1. Text-only regression — PASS
- 3.776 s
- prompt: 32 tokens
- completion: 6 tokens
- finish: stop
- response: `BONSAI_TEXT_OK`

### 2. Single-image OCR baseline — PASS
- 13.933 s
- prompt: 109 tokens
- completion: 26 tokens
- finish: stop
- output:
  `Riverside CafÃ©, COFFEE, TEA, DESSERT, Espresso, Latte, Cappuccino, Mocha`

### 3. Two-image left/right — PASS
- 24.515 s
- prompt: 181 tokens
- completion: 55 tokens
- finish: stop
- Image 1 correctly described the woman/dog/lake/mountain scene.
- Image 2 correctly described the green train/cherry-blossom/pedestrian scene.
- Comparison kept the two scenes distinct.

### 4. Four-image rejection — PASS
- error code: `too_many_images`
- structured OpenAI-style invalid-request response returned.

### 5. Invalid-image rejection — PASS
- error code: `invalid_image_data`
- structured OpenAI-style invalid-request response returned.

### 6. API survival after expected errors — PASS
- 4.995 s
- response: `BONSAI_API_SURVIVED`
- API remained running.

## Stability evidence

At the end of certification:

- API running: true
- last_error: none
- final stage: `TEXT_99_PASS`
- thermal state: nominal
- Low Power Mode: false
- app scene: active
- Metal allocated: about 6109 MiB
- Metal recommended: 8192 MiB

The final text request completed after the two expected request errors, proving
that validation errors did not poison the resident API runtime.

## OCR comparison

The single-image OCR baseline and the earlier three-image compact probe both
recognized menu content successfully. The visible `CafÃ©` mojibake appears in
the single-image baseline as well, so current evidence does **not** support
attributing that character corruption to the three-image contact-sheet adapter.

The three-image probe intentionally requested only six OCR items, while the
single-image baseline requested up to eight, so the item-count difference is
not evidence of contact-sheet OCR regression.

## Known non-blocking issues

These do not block RC1.25.0 certification:

1. Successful multi-image performance rows can still be recorded as
   `route=vision` instead of `route=vision_multi`.
2. Context admission failure text can report the required total context as
   "Prompt 已占用 N tokens", even though it includes input positions,
   requested output budget, and the reserve position.
3. The `Café` output can appear as `CafÃ©` in the Windows/JSON display path;
   root cause is not yet isolated.

## Frozen conclusion

RC1.25.0 Build 57 is accepted as the frozen multi-image functional baseline.

Production defaults remain unchanged from the certified Full runtime:

- context 512
- batch 8
- ubatch 8
- Flash Attention ON
- KQV Offload ON
- Op Offload ON
- unified KV ON
- mmap
