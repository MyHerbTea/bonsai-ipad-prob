# RC1.25.1 Build 60 — Device Certification Evidence

Status: **DEVICE CERTIFIED / FROZEN**

Frozen source commit: `5fc6e1cfaea4feb188b0635e26b9772ada83d303`

Frozen branch: `frozen-v1-rc1-25-1-build60-device-certified`

## Scope certified

RC1.25.1 preserves the RC1.25.0 1–3 image OpenAI-compatible API baseline and
adds three correctness/observability hardenings:

1. `vision_multi` success telemetry preserves the real route.
2. Non-stream JSON explicitly declares UTF-8.
3. Vision context admission checks both logical M-RoPE positions and physical
   KV-cell occupancy before native decode, returning a structured context error
   rather than a late generic injection failure.

No BVCACHE1 format, MLX vision math, contact-sheet layout, model weights, or
production decode architecture is redesigned in this release.

## CI evidence

GitHub Actions:

- Run: **#87**
- Run ID: `37259610302`
- Result: **PASS**
- Tested source SHA:
  `5fc6e1cfaea4feb188b0635e26b9772ada83d303`

The run passed the inherited RC1.23.x / RC1.24.x contracts, RC1.25.0
multi-image contracts, RC1.25.1 API hardening contracts, the Build 60 dual
context-admission contract, Swift syntax preflight, generated Xcode project,
full Xcode build, symbol verification, IPA packaging, and artifact upload.

Artifact:

- Name: `BonsaiLab-iPad-v1-RC1.25.1-Build60-Dual-Context-Admission`
- Artifact ID: `11323884102`
- Artifact digest:
  `sha256:c9b696dacb3cea3d2578a82cb04cbd152fe2cc27fa51ad88d1acf38fdcb85bd1`
- IPA:
  `BonsaiLab-v1-RC1.25.1-build60-dual-context-admission-unsigned.ipa`
- Verified IPA SHA-256:
  `af0795754e2f6995ebb165eae09c418b6e8574b04d426acaf0e3c1f68ad5337e`

The IPA checksum was independently recomputed from the downloaded CI artifact
and matched the packaged `.sha256` file.

## Device

Device snapshot:

- app_version: `1.0.0`
- build: `60`
- OS: `iPadOS 27.0.1`
- physical memory: `11524 MiB`

App state:

- `RC1.25.1 Build 60 Dual Context Admission 已预热`
- API running: `true`
- model: `bonsai-2-27b-local`
- main model: `Ternary-Bonsai-2-27B-PTQ1_0.gguf`
- vision tower: `Bonsai-2-27B-vision_tower-fp16.safetensors`

Production runtime remained on the frozen Full/Accelerated profile:

- API context: `512`
- batch / ubatch: `8 / 8`
- Flash Attention: ON
- KQV offload: ON
- Op offload: ON
- unified KV: ON
- load mode: `mmap`
- vision prefix KV reuse: ON

## Device certification runner

The Build 60 certification runner reached its final PASS gate. That gate only
succeeds when both conditions below hold:

### Test 1 — oversized 3-image context admission

PASS requirements enforced by the runner:

- HTTP status is `400`;
- error code contains `context_length_exceeded`;
- response contains:
  - `input_positions=`
  - `prompt_kv_tokens=`
  - `requested_output_tokens=256`
  - `required_context=`
  - `configured_context=512`
  - `maximum_safe_output=`

This verifies that the oversized request is rejected by the structured
pre-decode context-admission path rather than surfacing the Build 59 late
`llama_decode() code=1` / HTTP 500 failure.

### Test 2 — valid 2-image regression

PASS requirements enforced by the runner:

- HTTP status is `200`;
- response body parses as OpenAI-style JSON;
- assistant content is non-empty.

The subsequent device diagnostic independently confirms the successful request
remained on the intended multi-image route.

## Diagnostic evidence

The final snapshot reports two API requests.

### Request 1

- ordinal: `1`
- route: `vision_multi`
- result: `failed_or_interrupted`
- total: `522.808 ms`
- terminal stage: `API_REQUEST_FAIL_CONTEXT_CLEARED`
- thermal start/end: `nominal / nominal`

This is consistent with the certification runner's intentionally rejected
oversized request and confirms failure cleanup completed.

### Request 2

- ordinal: `2`
- route: `vision_multi`
- result: `success`
- requested/effective max tokens: `96 / 96`
- prompt tokens: `147`
- completion tokens: `96`
- finish reason: `length`
- total: `22108.835 ms`
- prefill: `14261.853 ms`
- decode: `7397.468 ms`
- decode throughput: `12.977 tok/s`
- thermal start/end: `nominal / nominal`

Multi-image adapter evidence:

- image count: `2`
- layout: `left-right`
- adapter: `bounded_contact_sheet_before_vision_tower`
- image ordering: `multiple`
- source: `1024x512`
- vision output: `55 x 5120`
- grid: `5x11`
- n_pos: `11`
- prefix reuse: MISS, retained=true

The API remained running after the rejected request and the subsequent valid
two-image request.

## UTF-8 scope

The explicit `application/json; charset=utf-8` hardening was device-verified
earlier in this RC1.25.1 line with a text-only response containing `Café`
as Unicode `U+00E9`. Build 60 does not modify that transport path.

That evidence establishes the scoped HTTP/JSON UTF-8 transport behavior. It
does **not** by itself establish the historical vision OCR `CafÃ©` root cause.

## Frozen conclusions

RC1.25.1 Build 60 is accepted as the device-certified baseline for:

- 1–3 image OpenAI-compatible requests;
- bounded 2/3-image contact-sheet adaptation;
- correct `vision_multi` route observability;
- explicit UTF-8 JSON transport declaration;
- structured dual-budget context rejection before native decode;
- API survival and valid multi-image inference after a rejected request.

Known inherited constraints remain:

- production API context is 512;
- API generation is capped at 256 completion tokens in the current production
  path;
- 2/3 images are adapted into one bounded contact sheet rather than independent
  native vision token blocks;
- sustained decode slowdown characteristics from RC1.24 remain unchanged;
- this certification is not a long-soak memory-leak proof.

Do not modify this frozen branch after the evidence/manifest freeze is complete.
