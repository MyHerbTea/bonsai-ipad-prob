# RC1.25.0 Build 57 — Multi-Image OpenAI API

Status: **DEVICE TEST CANDIDATE**

Parent baseline:
- RC1.24.1 Build 56 frozen runtime-profile attribution baseline.
- Production runtime remains Full / Accelerated.
- No native bridge, context, batch, ubatch, model-loading, or decode-path change.

## Goal

Extend the local OpenAI-compatible /v1/chat/completions endpoint from
single-image requests to bounded **1–3 image** requests while preserving the
already-certified resident 27B + MLX Vision path.

## API contract

Accepted image parts:
- type: image_url
- image_url.url: data:image/png;base64,...
- image_url.url: data:image/jpeg;base64,...

Images must:
- belong to the effective user turn;
- be supplied in the same user message as the effective text prompt;
- use PNG or JPEG data URLs;
- pass the existing per-image dimension/byte safety limits;
- fit the aggregate request pixel/decoded-byte limits.

Maximum images per request: **3**.

Four or more images return:
- HTTP 400
- code: too_many_images

Remote HTTP/HTTPS image fetch remains intentionally unsupported.

## Execution strategy

The frozen BVCACHE1/native bridge accepts one vision grid. RC1.25.0 therefore
does not modify the native bridge.

- 1 image: unchanged RC1.23.x path.
- 2 images: an ordered left/right contact sheet is created before the MLX Vision Tower.
- 3 images: an ordered left/center/right contact sheet is created before the MLX Vision Tower.

The contact sheet is bounded to 1024x512, aspect-fit per source image,
EXIF-orientation aware, separated by visible dividers, and encoded as JPEG
before the existing Vision Tower path.

The user prompt receives a short internal prefix explaining the image ordering
so references such as Image 1 / Image 2 / Image 3 remain meaningful.

This is a **compatibility adapter**, not native multiple independent vision token blocks.

## Safety and memory

The normalizer retains the existing single-image limits and adds aggregate
limits across all images. The compositor requests bounded thumbnails rather
than decoding every source image at full native resolution.

## Diagnostics

The full diagnostic snapshot adds:
- [RC1.25.0 MULTI-IMAGE]
- max_images_per_request=3
- last_api_image_count
- last_multi_image_layout
- adapter=bounded_contact_sheet_before_vision_tower

Expected layouts:
- 0 images: none
- 1 image: single
- 2 images: left-right
- 3 images: left-center-right

## Device acceptance

Build 57 is not frozen until a real iPad test passes all of:
1. text-only request still passes;
2. existing single-image request still passes;
3. two-image request returns a coherent comparison;
4. three-image request returns a coherent comparison;
5. four-image request returns too_many_images;
6. invalid image input returns a structured OpenAI-style error;
7. API remains alive after both success and expected error cases;
8. full diagnostic snapshot reports correct image count/layout.

The supplied tools/rc1250_three_image_probe.ps1 is the first device probe.
