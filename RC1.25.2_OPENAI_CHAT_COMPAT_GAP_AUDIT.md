# RC1.25.2 — OpenAI Chat Completions Compatibility Gap Audit

Status: Build 61 development baseline

Reference surface: current OpenAI Chat Completions API reference plus the
real-client behavior already checked for Chatbox.

## Target

RC1.25.2 targets a **truthful, useful subset** of OpenAI Chat Completions.
It does not claim that every OpenAI parameter or endpoint is implemented.

The acceptance standard is:

1. common clients can discover the model and its active context;
2. ordinary text, streaming, multimodal, and multi-turn chat work;
3. supported generation controls actually affect generation;
4. unsupported semantic features fail explicitly instead of being silently
   ignored;
5. errors remain machine-readable;
6. the service survives rejected requests.

## Chat Completions request coverage

### Supported

- `model`
- `messages`
  - `system`
  - `developer`
  - `user`
  - `assistant`
- string text content
- text content parts
- image URL content parts when the URL is a PNG/JPEG data URL
- 1–3 images per active visual user turn
- `max_tokens`
- `max_completion_tokens`
- local compatibility alias `max_output_tokens`
- `temperature`
- `top_p`
- `seed`
- `stream`
- `stream_options.include_usage`
- `response_format.type="text"`
- `n=1`
- `tool_choice="none"` compatibility mode

### Accepted harmless/default values

These do not change semantics and are allowed:

- empty `stop`
- `frequency_penalty=0`
- `presence_penalty=0`
- `logprobs=false`
- `top_logprobs=0`

### Explicitly unsupported

- actual function/tool execution
- `tool` / legacy `function` replay messages
- non-text structured `response_format`
- remote image fetching
- audio input/output
- files
- multiple candidates (`n > 1`)
- non-empty stop sequences
- non-zero frequency/presence penalties
- logprobs
- Responses API
- reasoning-model semantics

Unsupported semantic features return a machine-readable HTTP 400 rather than
being silently ignored.

## Response coverage

### Non-stream

Build 61 returns the standard Chat Completions shape needed by SDKs and
Chatbox:

- `id`
- `object="chat.completion"`
- `created`
- `model`
- `choices[0].index`
- `choices[0].message.role="assistant"`
- `choices[0].message.content`
- `choices[0].finish_reason`
- `usage.prompt_tokens`
- `usage.completion_tokens`
- `usage.total_tokens`

### Stream

Build 61 emits SSE data records with:

- `object="chat.completion.chunk"`
- initial assistant role delta
- text content deltas
- terminal finish-reason chunk
- optional final usage chunk when `stream_options.include_usage=true`
- `data: [DONE]`

## Message-history adapter

The local inference engine does not expose an arbitrary OpenAI conversation
object directly. Build 61 therefore normalizes client messages into the proven
local two-prompt contract:

- system/developer instructions -> instruction section;
- previous user/assistant text -> explicit conversation-history section;
- latest user text -> active user question.

For visual follow-ups, the most recent previous user image turn is re-injected
as the active visual source while the latest user text remains the active
question. Older visual turns are not simultaneously attended.

This adapter must remain visible in documentation; it is not equivalent to an
unbounded native multimodal conversation cache.

## Model discovery

OpenAI's standard model object is small, while local clients often need more
metadata. Build 61 keeps the standard fields and adds compatibility metadata:

- `id`
- `object="model"`
- `created`
- `owned_by`
- additive `name`
- additive `context_length`
- additive `context_window`
- additive `max_output_tokens`
- additive modality metadata
- additive `supported_parameters`
- additive capability metadata

Unknown additive fields can be ignored by strict clients. Chatbox consumes
`context_length` and image input modality metadata.

## Transport compatibility

Build 61 supports:

- Bearer authentication
- `X-API-Key` compatibility alias
- request bodies with Content-Length
- request bodies with chunked transfer encoding
- UTF-8 JSON
- chunked SSE responses
- browser CORS preflight
- private-network CORS opt-in
- common OpenAI SDK `OpenAI-*` and `X-Stainless-*` request headers

## Context contract

The active runtime context is the advertised context. A paused listener cannot
resume an old 512 runtime while advertising 1024 or 2048.

Candidate ladder:

- 512: frozen baseline
- 768: candidate
- 1024: preferred practical target if stable
- 2048: upper-bound candidate

Text and vision overflow both map to HTTP 400
`context_length_exceeded`.

## Deferred work

The following belong to later releases unless real-client evidence makes them
necessary for basic Chat Completions usability:

- Function Calling / Tools execution
- Responses API
- JSON Schema / structured output
- remote image retrieval
- audio
- files
- persistent server-side conversations
- arbitrary old-image simultaneous attention
- service tiers / hosted OpenAI-specific infrastructure controls

RC1.25.2 should finish Context + Chat Completions client compatibility before
opening any of those scopes.
