# Bonsai iPad Lab — RC1.11+ Roadmap

## Frozen evidence baseline

Validated on the target M5 iPad:

- PTQ1_0 text inference works locally through the pinned Prism runtime.
- Q8_0 mmproj loads successfully by itself.
- Main-model + projector coexistence is possible, but creating a llama context while the projector remains resident is unsafe.
- The Strata-style staged path works:
  1. vocab-only text metadata
  2. Q8 projector image encode
  3. copy vision embeddings / M-RoPE positions
  4. release projector completely
  5. load full PTQ1_0
  6. create llama context
  7. inject cached embeddings and decode
- 512 / 768 / 1024 vision presets all complete on-device.
- RC1.10.2 removes the temporary 64-token output cap.
- M5 tensor-API workaround stays enabled because the official Bonsai demo documents the same M5/A19 workaround; it preserves ordinary Metal and only skips the tensor-API / Neural Accelerator prefill path.

## Reference projects and what we borrow

### PrismML-Eng/Bonsai-demo

Authoritative for:
- pinned Prism runtime behavior
- Bonsai 2 model/mmproj pairing
- Metal / GPU layer behavior
- M5 tensor-API workaround
- Flash Attention default
- image-token guidance

### Niko1221/Strata

Borrow architecture, not platform-specific process design:
- vision encoder produces embeddings independently of text generation
- projector can be released after encoding
- image embeddings can be cached by image hash
- OpenAI-compatible vision requests use image_url blocks
- one-request-at-a-time FIFO is acceptable
- context overflow is handled explicitly, not by silent truncation
- request metrics and watchdog stages are first-class

### PocketPal AI / llama.rn

Borrow product and reliability patterns:
- simple defaults + Advanced Settings
- device-aware memory warnings instead of exposing every raw knob
- serialize model load/release operations
- preserve diagnostic state across failures
- prompt/session cache reuse where safe
- local-network permission handling on iOS
- multimodal context-size capability reporting

### llama.cpp server

Protocol reference for the final LAN API:
- GET /v1/models
- POST /v1/chat/completions
- OpenAI message/content shapes
- image_url data-URL support
- explicit non-streaming first, streaming later
- predictable JSON error objects

## Iteration plan

### RC1.11 — Vision Stabilization / Performance

Goal: separate correctness from performance.

Changes:
- dynamic output budget
- accelerated LLM context after projector release:
  - Flash Attention ON
  - KQV offload ON
  - op offload ON
- safe fallback mode retained
- tok/s shown in diagnostics
- no changes to vision embeddings, M-RoPE, or staged lifecycle

Gate:
- accelerated mode must complete on 512, 768, and 1024.
- compare tok/s with safe mode on the same image/prompt.

### RC1.12 — Production UX / Reliability

Goal: make the working baseline understandable without losing diagnostics.

Changes:
- user-facing quality presets:
  - Fast = 512
  - Standard = 768
  - Detailed = 1024
- answer-length presets:
  - Short = 128
  - Standard = 256
  - Detailed = 384
- Advanced disclosure contains raw knobs and native stages.
- map persisted native failure stage to an actionable recovery hint.
- remove misleading vision sampling controls from the normal UI.

Gate:
- a new user should only need model + mmproj + image + question + Analyze.
- raw diagnostics remain available when troubleshooting.

### RC1.13 — Image Embedding Cache

Goal: avoid repeating the 3–7 s image encoder work for the same picture.

Design:
- cache a versioned vision-embedding packet by SHA-256(image bytes) + mmproj identity + image-token preset.
- cache stores projection width, token count, M-RoPE metadata/positions, and float embeddings.
- bounded LRU cache with clear-cache control.
- cache is invalidated by packet version, mmproj change, or vision preset change.

Gate:
- first request = cache miss.
- second request on same image = cache hit and skips projector encode.
- changed image = cache miss.
- answers remain grounded and no stale-image leakage.

### RC1.14 — Resident LLM Session

Goal: avoid the ~4–6 s full-model reload between repeated questions when the projector is no longer needed.

Design:
- after an image has a valid embedding cache, keep full PTQ1_0 mmap model resident.
- recreate/reset llama context per independent request while keeping weights loaded.
- serialized actor/mutex: exactly one inference at a time.
- explicit release on memory warning / app background / user unload.
- safe fallback to cold staged execution.

Gate:
- same cached image, second question skips both projector encode and full model load.
- switching to a new uncached image releases the resident LLM before projector loading.
- no stale KV state leaks between chats.

### RC1.15 — OpenAI-Compatible LAN API

Goal: allow other devices on the LAN to use the iPad as a single-user local AI appliance.

Initial endpoints:
- GET /health
- GET /v1/models
- POST /v1/chat/completions

Initial compatibility:
- stream=false first
- text messages
- multimodal user content with image_url data URLs
- max_tokens
- model field accepted as Bonsai alias
- standard OpenAI-like choices/message/usage envelope
- JSON error envelope
- one request at a time; later requests wait or receive a clear busy response

iOS server:
- Network.framework / NWListener
- explicit Start/Stop switch
- visible LAN address + port
- NSLocalNetworkUsageDescription
- optional API key
- foreground-only behavior documented; no claim of unrestricted iOS background serving

Gate:
- Python openai client on another LAN device can call:
  - models
  - text chat
  - one-image chat
- API responses use the same inference coordinator as the UI.

### RC1.16 — Release Hardening

Goal: freeze a usable app, not a lab.

Changes:
- first-run setup checklist
- remembered model/mmproj bookmarks where iOS security-scoped access allows it
- bounded caches and cleanup
- structured diagnostic export
- memory-pressure recovery
- API request timeout / cancellation
- concise production UI; Lab diagnostics remain behind Advanced
- regression matrix for text, three vision categories, repeated same-image requests, new-image cache invalidation, API text, API vision

Release gate:
- no known crash in the supported 512/768/1024 presets
- output is never silently capped at 64
- errors surface a stage + recovery action
- same-image repeated requests demonstrate cache savings
- LAN API passes OpenAI-client smoke tests
