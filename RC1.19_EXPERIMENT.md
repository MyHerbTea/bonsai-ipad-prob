# RC1.19 — OpenAI Compatibility Hardening

Derived from the green RC1.18 resource-governor candidate.

## Added
- GET /v1/models/{id}
- request model validation with model_not_found
- stream_options.include_usage
- finish_reason = stop or length
- explicit n=1 contract
- explicit rejection of tools/tool_choice instead of silently ignoring them
- richer /health capability fields

## Preserved
- stream=false JSON chat completions
- true chunked SSE streaming
- data URL vision input
- persistent image/model/context/KV reuse
- automatic resource governor

This remains a single-user, serialized local inference service.
