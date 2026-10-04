# RC1.23.4 Generation / Decode Efficiency — Build 46

Status: **FROZEN — superseded as the stage entry point by `RC1.23.4_FROZEN_BASELINE.md`**

Parent baseline: RC1.23.3 build 45 FROZEN.

Frozen executable source: `4c0a453339350c0c915578a46a15d4235ab0ff99`.
Validation CI: run #37 (`37202037952`) — SUCCESS.

This document preserves the Build 46 design intent. For authoritative frozen evidence, invariants, device acceptance, and next-stage boundaries, use `RC1.23.4_FROZEN_BASELINE.md` and `RC1.23.4_FROZEN_MANIFEST.json`.

## Goal

Build 46 does not change generation policy. It makes termination behavior
observable so later optimization is based on evidence rather than token-budget
guessing.

## Read-only audit findings carried into build 46

1. `max_completion_tokens` takes precedence over `max_tokens`.
2. Request parsing accepts 1...2048, while the product execution layer caps the
   effective generation budget at 256.
3. The decode loop already stops early when `llama_vocab_is_eog()` is true.
   A 128-token result therefore means no EOG was sampled before the budget was
   exhausted; 128 is not an unconditional loop count.
4. The OpenAI `finish_reason` was inferred from generated-token count rather
   than propagated from the decoder.
5. The current LAN API does not parse OpenAI `stop` sequences. Build 46 records
   this as a compatibility gap but does not add stop-sequence behavior.

## Build 46 changes

- Add `GenerationTerminationReason` with `eog` and `length`.
- Propagate the actual decoder termination reason into `GenerationMetrics`.
- Record the effective generation budget in `GenerationMetrics`.
- Record API-requested and effective max tokens separately.
- Record termination reason and mapped OpenAI finish reason in diagnostics.
- Use decoder provenance to produce OpenAI `finish_reason` instead of inferring
  it from token count.
- Keep the frozen Full / Accelerated runtime, Safe fallback, C2-B checkpoint,
  Vision Prefix KV reuse, model, sampler settings, and answer policy unchanged.

## Telemetry fields

For successful text and vision API requests, diagnostics now include:

- `requested_max_tokens`
- `effective_max_tokens`
- `completion_tokens`
- `termination_reason=eog|length`
- `finish_reason=stop|length`
- `ttft_ms`
- `decode_ms`
- `tokens_per_second`
- `total_ms`

Existing vision prefill and C2-B fields remain available.

## True-device matrix

Use `tools/rc1234_generation_probe.ps1`.

Run the same text prompt and the same image+vision prompt at:

- 32 tokens
- 64 tokens
- 128 tokens

After the six requests, copy the full Diagnostic Snapshot. The history is the
authoritative source for requested/effective budgets and termination provenance.

## Decision gate for build 47

Do not promote a shorter automatic output budget merely because it is faster.

Classify each answer as complete or truncated and compare:

- requested budget;
- effective budget;
- generated tokens;
- `eog` versus `length`;
- finish reason;
- latency;
- answer completeness.

If 32/64 truncate but a larger budget reaches EOG naturally, budget reduction is
not an optimization. If even much larger budgets repeatedly terminate by
`length`, investigate prompt/template/EOG semantics before changing product
defaults.
