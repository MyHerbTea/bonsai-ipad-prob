# RC1.25.2 — OpenAI API Compatibility & Usability

Status: **Build 61 implementation candidate**

Parent frozen baseline:

- RC1.25.1 Build 60 — DEVICE CERTIFIED / FROZEN
- frozen evidence head: `01ef30bc755741a14a605178e2806f09ef6a9537`

## Goal

Turn the local endpoint from a narrowly compatible API into a client-friendly
OpenAI-compatible service. The first priority is context-window usability,
because context capacity affects whether real chat clients can send history,
system prompts, images, and an output budget without immediate rejection.

This release does **not** add function calling or the Responses API.

## Build 61 scope

### 1. API Context Ladder

The production UI exposes four explicit API context candidates:

- 512 — frozen Build 60 baseline
- 768 — validation candidate
- 1024 — target candidate
- 2048 — upper-bound exploration candidate

512 remains the default. Context cannot be changed while the API listener is
running; the user stops the API, selects a context, and prewarms again.

No 256 API context option is restored. The earlier 256 experiment remains
rejected.

### 2. Model discovery becomes useful

`GET /v1/models` and `GET /v1/models/{id}` advertise the active server
configuration using additive compatibility metadata:

- `context_length`
- `max_output_tokens`
- `architecture.input_modalities = ["text", "image"]`
- `architecture.output_modalities = ["text"]`
- `supported_parameters`
- capability booleans

The shape intentionally includes fields already consumed by Chatbox's
OpenAI-compatible model discovery path. In particular, Chatbox reads
`context_length` and `architecture.input_modalities`, so a newly fetched
Bonsai model can learn the server context and Vision capability instead of
requiring the user to guess them manually.

The server deliberately does not advertise tool or reasoning support.

### 3. Honest capability surface

Build 61 advertises:

- chat: yes
- vision: yes
- streaming: yes
- max images/request: 3
- tools: no
- reasoning: no
- Responses API: no

The existing parser still rejects non-empty `tools` / `tool_choice`.
This preserves a clear failure contract until real function calling exists.

## Device exploration plan

Run the exact same request matrix at 512, 768, 1024, then 2048. Do not promote a
larger context just because the model loads.

For each context validate at minimum:

- text streaming
- text non-streaming
- single-image
- two-image
- three-image
- context-overflow structured rejection
- API survival after rejection
- Stop/Resume
- memory and Metal allocation
- prefill/decode latency and throughput

Promotion rule:

1. 512 is the immutable comparison baseline.
2. 768/1024/2048 must preserve Build 60 correctness.
3. Prefer the largest context that is repeatably stable without unacceptable
   memory pressure or a material regression in normal client use.
4. If 2048 is unstable, 1024 is an acceptable target; if 1024 is unstable,
   preserve 768 or 512 rather than forcing a larger number.

## Compatibility matrix planned after context certification

- curl
- Chatbox
- Python OpenAI SDK
- JavaScript/TypeScript OpenAI SDK
- Open WebUI
- LobeChat

The API standardization phase is complete only when discovery, ordinary text,
streaming, multimodal input, overflow errors, and capability mismatches behave
predictably across real clients.
