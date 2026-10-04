# RC1.23.5 Build 47 — Suffix Prefill Profiling

Status: **PHASE A OBSERVABILITY CANDIDATE**

Parent baseline: **RC1.23.4 Build 46 FROZEN**

## Goal

Build 47 Phase A does not optimize generation or prefill behavior.

It adds enough observability to answer one narrow question:

> On a warm C2-B Vision Prefix KV HIT, how efficiently is the request-specific
> suffix/question prefill using the configured batch capacity?

Only after true-device evidence answers that question may RC1.23.5 choose one
optimization direction.

## Frozen behavior preserved

This profiling candidate does not intentionally change:

- Accelerated runtime selection;
- Safe fallback;
- `n_seq_max=1`;
- C2-B checkpoint save/restore;
- Vision Prefix KV reuse identity/invalidation;
- model or sampler;
- output token budgets;
- EOG/length termination semantics;
- Build 46 telemetry field names or meanings;
- PowerShell 5.1 UTF-8 probe behavior.

New profiling fields are additive and use the `rc1235_` namespace.

## Native execution path audited

For the cached Vision API path:

1. `BonsaiPrefillCachedVision(...)` constructs:
   - prefix text;
   - image chunk;
   - request-specific suffix text.
2. On a warm Prefix KV HIT, `begin_index=2`.
3. Prefix text and image decoding are skipped.
4. Only the suffix chunk is sent to `decode_text_chunk(...)`.
5. `decode_text_chunk` slices the suffix into chunks of at most `n_batch`
   tokens and calls `llama_decode()` once per chunk.

The frozen API runtime uses:

- `n_batch=8`;
- `n_ubatch=8`.

Therefore the profiling target is the actual suffix decode loop, not the
unrelated Swift text-prefill helper.

## Additive profiling fields

Build 47 adds:

- `rc1235_suffix_tokens`
- `rc1235_suffix_decode_calls`
- `rc1235_suffix_batch_capacity`
- `rc1235_suffix_ubatch_capacity`
- `rc1235_suffix_last_batch_tokens`
- `rc1235_suffix_batch_utilization`
- `rc1235_suffix_ms_per_decode_call`

Definitions:

### suffix tokens

Number of token IDs passed through the request-specific suffix text prefill.

### suffix decode calls

Actual number of suffix `llama_decode()` calls made by
`decode_text_chunk`.

### batch capacity

Configured `n_batch` used by the native suffix prefill loop.

### ubatch capacity

Configured runtime `n_ubatch`. In the frozen runtime it is 8.

### last batch tokens

Token count in the final suffix decode call.

### batch utilization

```text
suffix_tokens / (suffix_decode_calls * suffix_batch_capacity)
```

This reports packing efficiency of the current loop. It does not claim to
measure GPU utilization.

### milliseconds per decode call

```text
suffix_prefill_ms / suffix_decode_calls
```

This is a derived wall-time diagnostic for controlled comparisons.

## True-device Phase A matrix

Use the frozen Build 46 prompts and device environment.

### Vision concise timing prompt

`Describe the person, the dog, and the background in this image using concise bullet points.`

### Vision descriptive realism prompt

`请描述这张图片中的人物、动物和背景。`

For timing decisions, compare identical prompts only.

For each prompt:

1. establish Prefix KV warm HIT;
2. run repeated warm requests;
3. capture the complete Diagnostic Snapshot;
4. retain idle gap and thermal state;
5. report mean and median for TTFT and suffix prefill.

## Decision logic

### Batched prefill candidate

Consider batched prefill only if the profile shows a meaningful number of
decode calls and evidence that the current call structure is the dominant
avoidable suffix-prefill cost.

Do not infer a win merely from a partially filled final batch.

### Dynamic context candidate

Consider dynamic context only if suffix batching already appears efficient and
controlled profiling shows meaningful context-related overhead that can be
reduced without changing caller-visible token semantics.

## One-optimization rule

Build 47 may choose **one** production optimization:

- batched suffix prefill; or
- dynamic context.

Do not implement both in the same candidate.

If profiling does not support either direction, keep Build 46 as the production
baseline and close RC1.23.5 with no optimization.

## Acceptance

Phase A is complete when true-device data can answer:

- exact suffix token count;
- exact suffix decode call count;
- batch packing efficiency;
- suffix-prefill milliseconds per decode call;
- TTFT contribution;
- stability across repeated warm HITs.

No latency improvement claim is made by this observability-only build.
