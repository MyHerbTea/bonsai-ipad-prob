# Bonsai iPad Productization / Optimization Protocol

## Frozen baseline

The real-device functional baseline is **RC1.11**.

The following files are treated as a frozen inference core unless a later
experiment explicitly declares a core change:

- `BonsaiLab/BonsaiEngine.swift`
- `BonsaiLab/StagedVisionBridge.h`
- `BonsaiLab/StagedVisionBridge.mm`

GitHub Actions compares them to commit:

`ef2dcfc3a17e824d18e5244e52b01c75a4c9ed6b`

A UI/API/reliability iteration must fail CI if it changes that core by accident.

## Why this exists

RC1.4-RC1.10 isolated the iPadOS memory problem and established the staged
vision architecture:

1. Load a vocab-only text model.
2. Load Q8 mmproj.
3. Encode the image and copy the projected embeddings.
4. Fully release mmproj.
5. Load PTQ1_0 27B.
6. Create the llama context.
7. Inject the cached image embeddings and M-RoPE positions.
8. Generate the answer.

RC1.11 then proved the accelerated LLM context path on-device.

Product work should therefore optimize **around** this pipeline before changing
the pipeline itself.

## Iteration gates

Every product version follows the same order.

### Gate 1 — Static/source checks

GitHub Actions must pass:

- Swift syntax preflight
- frozen staged-core diff
- product invariants
- XcodeGen generation
- full unsigned Release build
- Prism multimodal symbol check
- IPA packaging

No device deployment happens before this gate is green.

### Gate 2 — One-tap device certification

In the app:

1. Select PTQ1_0.
2. Select Q8 mmproj.
3. Select one representative image.
4. Open **Advanced & Diagnostics**.
5. Tap **Run Device Certification**.

The app runs the same 64-token prompt through:

- Fast
- Standard
- Detailed

and records:

- PASS / FAIL
- output tokens/s
- image encode time
- full-model load time

A build is not promoted if a profile that passed in the previous accepted
build regresses to FAIL.

### Gate 3 — UX/recovery smoke

Verify:

- one normal image question succeeds without opening developer settings;
- accelerated failure falls back to Safe automatically;
- an ordinary error is presented as a user-readable category;
- raw native stage remains available under diagnostics;
- no legacy diagnostic control is required for normal use.

### Gate 4 — LAN API smoke

With the app in the foreground and API enabled:

- `GET /health`
- authenticated `GET /v1/models`
- authenticated text `POST /v1/chat/completions`
- authenticated vision `POST /v1/chat/completions` using a data URL
- `stream=true` returns valid SSE framing

The first API milestone is intentionally single-request / serialized inference.
Concurrency is not a target.

## Optimization policy

Only promote an optimization when one of these improves without breaking the
others:

- output tokens/s;
- image encode latency;
- model load latency;
- successful context tier;
- answer completeness;
- crash-free repeated runs;
- user steps required per request.

Timing instrumentation stays in the binary because its overhead is negligible;
normal users only see a compact speed summary.

## Open-source ideas adopted

### Prism Bonsai-demo

- Prism fork / matching mmproj is the compatibility authority.
- M5 workaround `GGML_METAL_TENSOR_DISABLE=1` remains enabled.
- Metal remains enabled; the workaround only avoids the tensor-API path.

### Strata

- Vision encoder and text inference have separate lifetimes.
- Projected image embeddings are the handoff boundary.
- `clip.vision.projection_dim` is the projector-output width authority.
- OpenAI-style image messages use `image_url` data URLs.

### PocketPal / llama.rn

- Prefer device-calibrated memory decisions over physical-RAM heuristics.
- Serialize model lifecycle transitions.
- Preserve useful prompt/KV state when a future session implementation can do
  so safely.
- Keep raw diagnostics available without exposing them in the default UI.

## Version ladder

### RC1.12 — Production UX / Reliability

- Production UI is the default.
- Quality presets: Fast / Standard / Detailed.
- Answer-length presets.
- Automatic Accelerated -> Safe fallback.
- Friendly error classes.
- One-tap device certification.
- Legacy Lab remains under Developer Diagnostics.

### RC1.13 — OpenAI LAN API

- `/v1/models`
- `/v1/chat/completions`
- Bearer-key authentication
- text requests
- vision data-URL requests
- SSE-compatible response framing
- local-network-only design
- app must remain foreground

### Next optimization candidates

These must be benchmarked independently rather than bundled blindly:

1. same-image session reuse / prompt-state reuse;
2. persistent 27B model and context for follow-up questions;
3. cached image embeddings;
4. adaptive quality selection from measured device headroom;
5. only then evaluate MTP/speculative decoding if the Bonsai GGUF/runtime
   exposes a compatible draft path.

A feature is accepted only after the device certification matrix confirms that
it improves the product rather than merely adding complexity.


## RC1.15 product-session integration candidate

RC1.11 remains the last device-proven frozen inference core. RC1.15 is an
intentional performance candidate and therefore is **not** covered by the
"core must be byte-identical to RC1.11" rule.

RC1.15 integrates two previously separate lines:

- RC1.13 product UX + OpenAI-compatible LAN API;
- RC1.13 image embedding cache + RC1.14 resident full-model experiment.

The integration must preserve the RC1.14 native bridge files exactly, while
allowing a narrowly scoped Swift lifecycle fix so repeated staged-vision calls
do not release the resident model before it can be reused.

Promotion requires real-device evidence. For the same model, mmproj, image and
quality preset, a second request should report:

- `Image cache: HIT`;
- `Resident model: HIT`;
- near-zero image encode time;
- near-zero full-model load time.

The production view must also stop the LAN API and release resident model state
when the app enters the background. If any of these lifecycle conditions fail,
RC1.15 remains an experiment and RC1.13 stays the product baseline.
