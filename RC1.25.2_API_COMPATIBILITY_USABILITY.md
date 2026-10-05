# RC1.25.2 Build 61 — OpenAI API Compatibility & Usability

Status: **LAB / DEVICE BOUNDARY EXPLORATION**

Base frozen evidence head:
`01ef30bc755741a14a605178e2806f09ef6a9537`

Base release:
**RC1.25.1 Build 60 — DEVICE CERTIFIED / FROZEN**

## Goal

RC1.25.2 turns the LAN endpoint from a narrowly working OpenAI-compatible
surface into a client-usable API contract. The first priority is context-window
correctness because clients such as Chatbox make context-management decisions
from model limits.

Build 61 does **not** declare a larger context production-safe. It exposes a
bounded device-test matrix while keeping 512 as the default certified baseline.

## Build 61 scope

### 1. Bounded API Context profiles

The production API can be started with one of four explicit profiles:

- 512 — frozen RC1.25.1 baseline;
- 768 — exploration;
- 1024 — primary target;
- 2048 — stretch target.

The picker is disabled while the API is running. Changing the profile therefore
requires a normal stop/reload boundary and cannot silently mutate a resident
llama context.

### 2. Accurate model capability advertisement

`GET /v1/models` and `GET /v1/models/{id}` now return the active runtime
context rather than requiring clients or users to guess it.

The model object advertises:

- `context_window` — exact active API runtime context;
- `max_output_tokens=256` — current production generation cap;
- `max_images_per_request=3`;
- chat / vision / streaming / multi-image supported;
- tools / reasoning / Responses API not supported;
- text+image input and text output modalities.

These are Bonsai compatibility extension fields. They intentionally do not
pretend that OpenAI's core /models schema defines standardized capability
metadata; clients that ignore unknown fields remain compatible.

### 3. Frozen defaults preserved

Build 61 keeps the RC1.25.1 production defaults unless the user explicitly
selects an exploration context:

- context 512 by default;
- batch 8;
- ubatch 8;
- Accelerated runtime;
- Flash Attention ON;
- KQV offload ON;
- Op offload ON;
- unified KV ON;
- mmap loading;
- 256 effective API completion-token cap.

## Device boundary plan

Do not certify 768/1024/2048 from CI alone. Each context must be tested on the
target iPad with the same model and runtime profile.

For each candidate context, collect:

1. text-only short request;
2. text-only multi-turn request;
3. single-image request;
4. 2-image request;
5. 3-image request;
6. streaming and non-streaming;
7. context-overflow rejection;
8. Stop/Resume survival;
9. available/resident/physical-footprint/Metal diagnostics;
10. prefill/decode timing and thermal state.

Promotion policy:

- 512 remains the fallback oracle.
- 768 may be accepted only if it is regression-free.
- 1024 is the preferred production target if memory and latency remain stable.
- 2048 is optional; failure does not block RC1.25.2 if 1024 is stable.

## Explicitly out of scope for Build 61

- true OpenAI Function Calling / tool execution;
- Responses API;
- agent protocol;
- native independent multi-image token blocks;
- automatic context resizing while the runtime is resident;
- automatic client-specific configuration hacks.

Those remain later compatibility phases after the context contract is
device-certified.
