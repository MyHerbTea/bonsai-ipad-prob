# RC1.23.1 — OpenAI-Compatible Multimodal API

## Purpose

RC1.23.1 replaces only the LAN OpenAI API image backend. Text requests keep the frozen RC1.20.7 path. Image requests reuse the real-device-passed RC1.22.5 MLX Hard Graph-Cut Vision Tower and RC1.23.0 Live Vision Injection path.

## Frozen baselines

- RC1.20.7: resident 27B text runtime, OpenAI-style Chat Completions, true chunked SSE.
- RC1.22.5: MLX Hard Graph-Cut vision execution and memory lifecycle.
- RC1.23.0: MLX projected embeddings → BVCACHE1 → resident 27B prefill/decode.

No vision math, hard-graph-cut math, or text decode math is redesigned in this release.

## Supported API shape

Endpoint:

`POST /v1/chat/completions`

Image transport:

- one image maximum per request;
- `data:image/png;base64,...`;
- `data:image/jpeg;base64,...` / `image/jpg`;
- remote HTTP(S) image fetching is deliberately unsupported.

Text-only requests continue to use the existing text route.

## API image path

```text
OpenAI JSON
  → strict content normalization
  → bounded data-URL validation
  → temporary image file
  → MLXVisionSidecar.encodeForInjection
  → projected F32 [N, 5120]
  → BonsaiWriteProjectedVisionCache
  → BonsaiPrefillCachedVision
  → resident Bonsai-2-27B decode
  → existing JSON/SSE response
```

The API image path does not initialize mmproj and does not require an App restart.

## Runtime ordering constraint

Source inspection of the frozen RC1.23.0 prefill path shows that BVCACHE1 currently uses a fixed vision-first user layout:

```text
<|im_start|>user
<|vision_start|>[visual embeddings]<|vision_end|>
question
<|im_end|>
```

The request normalizer preserves client content-part ordering as metadata for diagnostics, but RC1.23.1 deliberately adapts a valid single-image request to this proven fixed runtime layout. It does not claim arbitrary interleaved multimodal placement.

## M-RoPE context accounting

Projected embedding rows are not equivalent to sequential context positions.

For the validated reference image:

- projected visual rows: 54;
- projection width: 5120;
- grid: 9 × 6;
- BVCACHE1 `n_pos`: 9.

`BonsaiWriteProjectedVisionCache` stores `n_pos = max(grid_x, grid_y)`, and `BonsaiPrefillCachedVision` returns the actual `input_positions` after text + vision prefill. RC1.23.1 uses that real prefill position for context admission.

For API requests, the full requested completion budget must fit. The API no longer silently shortens a multimodal completion merely to fit the active runtime context.

## Failure semantics

If an image is supplied, failures never fall back to text-only inference.

Structured errors include:

- `invalid_content_part`
- `invalid_image_url`
- `invalid_image_data`
- `unsupported_image_type`
- `remote_image_url_unsupported`
- `too_many_images`
- `image_too_large`
- `image_dimensions_too_large`
- `image_decode_failed`
- `vision_model_unavailable`
- `vision_embedding_invalid`
- `context_length_exceeded`
- `vision_inference_failed`
- `vision_injection_failed`

Streaming responses delay the HTTP 200/SSE start until the first generated delta. A failure before generation can therefore still return the correct HTTP error status and JSON envelope.

## Input protection

RC1.23.1 has layered limits:

1. existing HTTP request-body cap: 25 MiB;
2. inline encoded image limit;
3. decoded payload-byte limit;
4. metadata-level dimension/pixel-count validation before vision inference.

Raw base64 payloads are never logged.

## Failure cleanup

- native cached-vision prefill clears llama memory if a chunk decode fails;
- MLX request failure clears MLX cache through `cleanupAfterRequestFailure()`;
- temporary API image files are deleted with `defer`;
- a failed image request does not intentionally unload/reload the resident 27B model.

## Acceptance gates

Automated:
- strict parser/data-URL contracts;
- frozen baseline source invariants;
- Swift syntax preflight;
- full Release iOS Xcode build;
- IPA packaging.

Real device:
1. text-only API regression;
2. direct RC1.23.0 reference-image regression;
3. Windows → iPad single-image base64 request;
4. image-grounded semantic answer;
5. true SSE request;
6. invalid-image structured failure followed by successful text request;
7. text → image → text sequence with no stale visual state.

RC1.23.1 is not declared real-device PASS until those device gates complete.
