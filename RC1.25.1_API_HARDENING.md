# RC1.25.1 Build 58 — API Observability & Error Hardening

Status: **CI / DEVICE CANDIDATE**

Parent baseline: RC1.25.0 Build 57 device-certified frozen baseline.

## Scope

This is intentionally a small correctness and observability release. It does
not change the certified text, vision, contact-sheet, native BVCACHE1, or 27B
runtime architecture.

### 1. Multi-image route telemetry

RC1.25.0 computed `vision_multi` correctly at request admission, but the
success recorder hard-coded `route=vision`.

Build 58 passes the computed route into the success recorder, so two- and
three-image requests remain `vision_multi` in both latest-request diagnostics
and long-run history.

### 2. Context budget errors

The old `promptTooLong` wording could report a number containing input
positions + requested output + one reserve position as if all of it were
"Prompt" tokens.

Build 58 adds a dedicated API vision context-budget error containing:

- input_positions
- requested_output_tokens
- required_context
- configured_context
- maximum_safe_output

The HTTP code remains `context_length_exceeded`.

### 3. JSON UTF-8 transport declaration

SSE already declared `charset=utf-8`, while ordinary JSON replies used only
`application/json`.

Build 58 changes non-stream JSON replies to:

`Content-Type: application/json; charset=utf-8`

This is a transport hardening change. It does not by itself prove that the
previous `Café -> CafÃ©` observation originated in HTTP decoding. Device
testing must distinguish model/token output from client-side decoding.

## Frozen invariants

Unchanged:

- API context 512
- batch / ubatch 8 / 8
- Full / Accelerated production default
- Flash Attention ON
- KQV Offload ON
- Op Offload ON
- unified KV ON
- mmap
- 1–3 image API contract
- 2-image left/right adapter
- 3-image left/center/right adapter
- max 3 images
- structured image validation errors
