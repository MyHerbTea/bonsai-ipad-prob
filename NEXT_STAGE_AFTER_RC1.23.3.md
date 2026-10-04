# NEXT STAGE AFTER RC1.23.3

Start version: **RC1.23.4**
Stage: **Generation / Decode Efficiency**

## Authoritative parent

Use only the frozen RC1.23.3 build-45 baseline:

- source commit: `0e9b14746a85b2035f0d06b88197d338b8b8bc4a`;
- CI run #29: SUCCESS;
- artifact ID: `11301100823`;
- runtime default: Full / Accelerated;
- Safe remains the fallback;
- C2-B remains frozen.

Do not reopen RC1.23.3 runtime-profile A/B unless a regression appears.

## Problem statement

Current controlled multimodal requests frequently generate the entire requested
128-token completion budget. The decoder does stop on EOG, so 128 is a maximum,
not a hard-coded exact length; however, in the validated test prompt the model
often reaches that maximum. Decode therefore dominates end-to-end latency.

RC1.23.4 should determine whether latency can be reduced by improving generation
semantics and budget policy rather than by changing the frozen C2-B runtime.

## Required investigation order

1. Verify current OpenAI request parsing for `max_tokens` /
   `max_completion_tokens` and finish reasons.
2. Verify EOG and stop-token handling in the actual decode path.
3. Measure completion-length distribution for representative text and vision
   prompts at multiple budgets without changing model/runtime configuration.
4. Separate answer truncation from naturally completed answers.
5. Evaluate product-level answer-length presets or adaptive budgets only after
   the semantics above are proven.
6. Preserve streaming and non-streaming compatibility.
7. Preserve text recovery and multimodal error behavior.

## Frozen boundaries

Do not change during RC1.23.4 unless a regression forces reconsideration:

- build-45 Full/Accelerated runtime configuration;
- Safe fallback semantics;
- `n_seq_max=1`;
- C2-B checkpoint implementation;
- Vision Prefix KV reuse identity/invalidation;
- MLX Vision Tower and hard graph-cut path;
- projection width 5120;
- OpenAI multimodal normalization/error contract.

## First acceptance target

Produce an evidence-backed generation baseline that reports, for each controlled
request:

- requested completion budget;
- actual completion tokens;
- finish reason;
- EOG/stop versus length termination;
- TTFT;
- decode time;
- tokens/s;
- total latency;
- answer completeness classification.

No new automatic truncation policy should be promoted before this evidence gate.
