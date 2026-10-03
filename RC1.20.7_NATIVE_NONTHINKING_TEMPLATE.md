# RC1.20.7 — Native Non-Thinking Template

## Real-device evidence from RC1.20.6

The client sent:
- reasoning_effort = none
- max_completion_tokens = 128
- stream = true
- stream_options.include_usage = true

The server correctly honored the 128-token budget, but the model still emitted a full <think>...</think> block before the visible answer.

Therefore the natural-language "do not think" instruction was not a valid implementation of the model's native non-thinking mode.

## Upstream template behavior

The shipped Ternary-Bonsai / Qwen3.8 chat template implements enable_thinking=false by pre-filling:

<|im_start|>assistant
<think>

</think>

before generation.

The model therefore starts directly in answer mode rather than being instructed to suppress reasoning.

## RC1.20.7 change

- BonsaiEngine.generateText accepts an optional reasoningEffort.
- For reasoningEffort == none, makeSimpleChatPrompt appends the exact empty closed think block to the assistant generation prefix.
- The previous natural-language anti-reasoning instruction is removed.
- low/xhigh keep template-aligned reasoning instructions; medium adds no extra instruction.
- No post-generation string filtering is used.
- RC1.20.5 prewarmed runtime and RC1.20.6 256-token ceiling remain unchanged.
- LAN vision remains deliberately disabled with structured 503.

## Acceptance

Use reasoning_effort=none, max_completion_tokens=128, stream=true.

PASS:
- first generated content is the answer, not <think>;
- no generated </think> appears;
- completion budget is not silently capped at 64;
- true incremental SSE and [DONE] remain intact.
