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

Actual tool execution remains unsupported. Build 61 accepts the standards-safe
compatibility case `tool_choice="none"` (including harmless tool schemas that
cannot be invoked), while any request that may execute a tool is rejected.

### 4. Real multi-turn chat compatibility

Build 60 effectively consumed only the latest user text and did not preserve
ordinary assistant/user history as conversational context. Build 61 now
normalizes `system`, `developer`, `user`, and `assistant` messages:

- system/developer instructions are retained;
- previous user/assistant turns are compiled into an explicit conversation
  history section;
- the latest user turn remains the active generation turn;
- image binding remains restricted to the effective current user turn;
- tool-role/tool-call history is rejected until function calling exists.

This gives Chatbox and SDK clients meaningful multi-turn behavior without
changing the underlying proven two-input engine contract.

### 5. Context changes cannot fake a larger runtime

Stop/Resume preserves the resident runtime. That creates a subtle usability
risk: a user could stop the listener, change 512 to 1024, then resume the old
512 runtime.

Build 61 compares the requested Context/Profile against the active resident
runtime. If they match, only the listener is resumed. If either differs, the
old handler/runtime is released and the selected configuration is fully
prewarmed before the API returns to ready state. Model discovery is then
updated from the active runtime.

The UI explicitly distinguishes **Resume API** from **Apply settings and
re-prewarm API**.

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
