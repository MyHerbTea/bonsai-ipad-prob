# RC1.25.2 Client Compatibility Matrix

Status: Build 61 development baseline

## Why this exists

RC1.25.2 treats "OpenAI-compatible" as a real client contract rather than only
matching endpoint names. The server must be discoverable, reject unsupported
features clearly, preserve ordinary chat history, and survive common transport
differences between clients.

## Chatbox — current source behavior checked

The current Chatbox OpenAI-compatible path performs model discovery with:

- `GET {apiHost}/models`
- `Authorization: Bearer <key>`

For every returned model Chatbox consumes:

- `id`
- `context_length` -> model context window
- `architecture.input_modalities` containing `image` -> Vision capability

Chatbox does **not** infer Tool Use from the remote model response. Tool Use is
a local capability setting. This matches the device finding that Bonsai chats
work when Vision is enabled and Tool Use / Reasoning are disabled.

### Recommended Chatbox configuration

- Mode: OpenAI API Compatible
- API Host: the Bonsai host without manually adding a duplicate `/v1`
- API Path: blank/default `/chat/completions`
- Model: `bonsai-2-27b-local`
- Context Window: use discovered value
- Max Output Tokens: 128 recommended for the 512 baseline
- Vision: ON
- Reasoning: OFF
- Tool Use: OFF
- Auto Compaction: OFF while validating small contexts

The server maximum output remains 256. The 128 recommendation leaves more room
for prompt/history at the 512 baseline.

## Build 61 server contract

| Area | Build 61 behavior |
|---|---|
| Model discovery | `GET /v1/models`, `GET /v1/models/{id}` |
| Chat | `POST /v1/chat/completions` |
| Streaming | SSE + chunked response + `[DONE]` |
| Request body | Content-Length **or** chunked transfer encoding |
| Auth | Bearer API key; X-API-Key compatibility alias |
| Context discovery | `context_length` |
| Vision discovery | `architecture.input_modalities=["text","image"]` |
| Output budget aliases | `max_tokens`, `max_completion_tokens`, `max_output_tokens` |
| Sampling | `temperature`, `top_p`, `seed` |
| Response format | text only |
| Tools | actual tool execution unsupported |
| `tool_choice="none"` | accepted compatibility mode |
| Reasoning capability | not advertised |
| Multi-turn text | system/developer/user/assistant history preserved |
| Visual follow-up | most recent prior visual user turn can be reused |
| Max images per visual turn | 3 |
| Structured overflow | HTTP 400 `context_length_exceeded` |
| Parse errors | machine-readable error codes |
| 5xx inference errors | `type=server_error` |

## Context ladder

The candidate runtime ladder is:

- 512 — frozen Build 60 baseline
- 768 — validation candidate
- 1024 — preferred practical target if stable
- 2048 — upper-bound exploration

Changing Context/Profile while the listener is paused cannot silently reuse an
old runtime. Build 61 compares the selected configuration with the resident
runtime and fully re-prewarms when they differ.

## Planned client certification

After the context boundary is chosen, certify the same matrix against:

1. Chatbox
2. Python OpenAI SDK
3. JavaScript/TypeScript OpenAI SDK
4. Open WebUI
5. LobeChat

For every client test discovery, text non-stream, text stream, ordinary
multi-turn, single-image, visual follow-up, context overflow, unsupported
tools, and API survival after an error.
