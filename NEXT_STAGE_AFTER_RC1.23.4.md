# NEXT STAGE AFTER RC1.23.4

Start version: **RC1.23.5**
Target build: **47**
Stage: **TTFT & Suffix Prefill Efficiency**

## Authoritative parent

Use only the frozen RC1.23.4 Build 46 executable baseline:

- source commit: `4c0a453339350c0c915578a46a15d4235ab0ff99`;
- validation CI: run **#37**, run ID `37202037952`, SUCCESS;
- artifact ID: `11302983359`;
- runtime default: **Accelerated**;
- Safe remains the fallback;
- C2-B remains frozen;
- `n_seq_max=1`;
- generation telemetry schema remains frozen;
- decoder-provenance finish-reason mapping remains frozen.

Do not reopen RC1.23.4 EOG/termination investigation unless a new regression appears.

## What Build 46 established

Build 46 removed several false leads:

1. Text EOG is correct.
2. Vision EOG is correct under a controlled concise prompt.
3. Warm Vision decode throughput is in the same broad range as text decode throughput.
4. C2-B continues to eliminate warm prefix/image prefill.
5. Long descriptive answers can legitimately consume the full output budget.
6. Windows PowerShell 5.1 Unicode contamination was a test-harness problem and is fixed.

The next performance question is therefore narrower:

> After C2-B has removed reusable prefix/image work, how much of TTFT is still spent in suffix/question prefill, how efficiently is that suffix prefill batched, and can one evidence-backed optimization reduce it without changing frozen behavior?

## Stage rule: profile first, optimize second

Build 47 must not begin with a production optimization.

The first phase is controlled profiling only.

The profiling phase must answer:

- how many suffix prompt tokens are processed;
- how many prefill/decode calls are used for those suffix tokens;
- how full each prefill micro-batch is;
- whether `api_batch=8` / `api_ubatch=8` is underutilized or saturated;
- whether suffix-prefill wall time scales with suffix token count;
- whether TTFT variation is dominated by suffix prefill, device performance state, or another fixed cost;
- whether context-size overhead is measurable after controlling for prompt length.

## Frozen boundaries

RC1.23.5 must not silently change:

- Accelerated runtime selection;
- Safe fallback;
- Flash-only rejection;
- C2-B state format or save/restore behavior;
- `n_seq_max=1`;
- Vision Prefix KV reuse identity/invalidation;
- RC1.22.5 MLX hard graph-cut path;
- projection width 5120;
- Build 46 telemetry field meanings;
- EOG -> `stop` and budget exhaustion -> `length` mapping;
- OpenAI multimodal normalization/error semantics;
- the UTF-8-safe PowerShell probe.

Any candidate violating those boundaries requires a separate architecture decision, not a Build 47 optimization.

## Phase A — Controlled suffix-prefill profiling

Use the Build 46 baseline first.

### Fixed environment

Keep constant:

- iPad Pro M5 / 12 GB;
- same OS version during an A/B session;
- same model;
- same Vision Tower;
- same image;
- Accelerated runtime;
- `api_context=512`;
- `api_batch=8`;
- `api_ubatch=8`;
- `n_seq_max=1`;
- same C2-B warm HIT state;
- same max completion tokens;
- `reasoning_effort=none`;
- same prompt within each comparison group.

### Controlled prompts

Text concise:

`Reply with one concise sentence describing why the sky appears blue.`

Vision concise:

`Describe the person, the dog, and the background in this image using concise bullet points.`

Vision descriptive UTF-8 control:

`请描述这张图片中的人物、动物和背景。`

Use the concise prompts for timing A/B. Use the descriptive prompt as a product-realism check, not as a timing-equivalent replacement.

### Required new profiling evidence

Before changing runtime behavior, add or derive enough telemetry to report at least:

- suffix prompt token count;
- prefill call count;
- tokens processed per prefill call;
- effective batch occupancy;
- `prefill_ms`;
- `suffix_prefill_ms`;
- `ttft_ms`;
- `decode_ms`;
- `tokens_per_second`;
- total latency;
- completion tokens;
- termination reason;
- prefix reuse hit/retained state;
- thermal state and idle gap.

If the existing implementation cannot expose batch occupancy without instrumentation, Build 47 Phase A may add observability-only telemetry first. That observability change must not alter generation behavior.

## Repetition and statistics

Do not select an optimization from one timing sample.

For each controlled case:

- establish the warm C2-B state;
- collect multiple warm requests;
- preserve request order;
- record idle gap;
- report median and mean;
- keep best-case timing only as supplementary evidence;
- reject comparisons where cache state or prompt differs.

## Optimization decision gate

After Phase A, choose **exactly one** of the following candidate directions.

### Candidate A — Batched suffix prefill

Choose this only if profiling shows:

- suffix prefill is split into multiple small or underfilled calls;
- current effective batch occupancy is materially below what the implementation can safely process;
- increasing suffix-prefill batching can reduce call overhead without changing C2-B, decode semantics, or memory safety.

The implementation should then target suffix prefill only. It must not silently alter decode sampling, output budget, model, or Prefix KV identity.

### Candidate B — Dynamic context

Choose this only if profiling shows:

- suffix batch utilization is already efficient;
- context-size-related setup/KV overhead is measurable and meaningful;
- a smaller per-request effective context can be selected without truncating the fixed controlled prompts or changing OpenAI-visible token semantics.

Dynamic context must never lower the caller's effective output budget without an explicit, observable admission decision.

### Selection rule

Do **not** implement both in Build 47.

Select one candidate with the stronger measured bottleneck and the smaller regression surface.

If neither hypothesis is supported by profiling, stop Build 47 optimization work and preserve Build 46 rather than forcing a change.

## Build 47 A/B acceptance

Baseline:

- frozen RC1.23.4 Build 46.

Candidate:

- RC1.23.5 Build 47 with exactly one optimization.

Compare under identical controlled conditions.

Primary metrics:

- median `ttft_ms`;
- median `suffix_prefill_ms`;
- median `prefill_ms`;
- median total latency.

Guardrail metrics:

- decode tokens/s;
- completion tokens;
- termination reason;
- finish reason;
- Prefix KV HIT/retained;
- memory / Metal allocation;
- thermal state;
- HTTP success;
- answer equivalence/completeness.

A candidate is not accepted merely because one request is faster.

## Required non-regression outcomes

A successful Build 47 must preserve:

- API startup stability;
- text generation correctness;
- Vision generation correctness;
- natural EOG behavior;
- caller max-token semantics;
- C2-B HIT and retained behavior;
- zero warm prefix/image prefill;
- OpenAI finish-reason provenance;
- UTF-8 request/response correctness;
- no new monotonic memory growth;
- no crash.

## Phase completion

RC1.23.5 should end in one of two valid outcomes:

1. **Optimization accepted** — controlled A/B demonstrates a repeatable TTFT/suffix-prefill improvement with all guardrails passing.
2. **No safe win found** — evidence shows neither batched prefill nor dynamic context provides a worthwhile low-risk gain; Build 46 remains the production baseline.

Both are valid engineering outcomes. Do not trade frozen correctness for a marginal single-run latency win.
