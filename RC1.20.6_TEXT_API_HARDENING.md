# RC1.20.6 — Text API Hardening

Real-device RC1.20.5 evidence:
- non-stream chat completion returned HTTP 200;
- true chunked SSE produced many incremental chat.completion.chunk events;
- stream_options.include_usage emitted a final usage chunk;
- the stream terminated with data: [DONE];
- the request asked for 128 completion tokens but the product handler silently capped generation at 64, producing finish_reason=length;
- model reasoning appeared as literal <think> content because the local custom chat prompt had no reasoning-effort policy.

## Changes

- Preserve the RC1.20.5 prewarmed text-only runtime.
- Parse OpenAI-style reasoning_effort:
  - none (mobile default)
  - low
  - medium
  - xhigh
- Reject unsupported effort names explicitly.
- For none, add a direct-answer system instruction that forbids exposed chain-of-thought and <think> tags.
- Raise the product handler ceiling from 64 to 256 output tokens so a client request for 128 is honored.
- /health advertises default_reasoning_effort=none and max_output_tokens=256.
- Vision remains intentionally unavailable over LAN API until the two-phase projector/embedding architecture is ready.

## Real-device acceptance

1. Send stream=false with max_completion_tokens=128 and reasoning_effort=none.
2. Expect HTTP 200, no leading <think>, and no artificial 64-token length cutoff.
3. Send stream=true with include_usage; expect incremental chunks and [DONE].
4. Send invalid reasoning_effort=high; expect HTTP 400 rather than inference execution.
