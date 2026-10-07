# RC1.26 Next Stage — Text Context Efficiency Before Capacity Expansion

## Decision

The next product optimization should address **text history reuse**, not raw decode speed.

Build 75 demonstrates:
- ~13 tok/s sustained decode for short prompts;
- stable 32×32 prefill configuration;
- reliable API cold start;
- functional 2048-token capacity;
- unacceptable full-history re-prefill latency near context capacity.

Current text generation clears working KV at request start and evaluates the submitted prompt again. For OpenAI-style multi-turn requests, clients resend the conversation history, so latency scales with the full accumulated prompt.

## Proposed sequence

### Phase 2I0 — source/contract design
No product behavior change.
- inspect llama/Prism memory sequence APIs available in the pinned framework;
- define exact longest-common-prefix token semantics;
- define cache invalidation on model/context/profile/system-prompt changes;
- define failure fallback to current full-clear/full-prefill path;
- ensure streaming/non-streaming output equivalence.

### Build 76 — Text Prefix/KV Reuse Lab
One isolated behavior change:
- keep previous request token prefix and KV state when safe;
- for a new request, calculate token-level longest common prefix;
- reuse valid KV prefix;
- evaluate only the changed suffix;
- fallback to frozen Build 75 path whenever reuse cannot be proven safe.

A/B:
- baseline: Build 75 full clear/full prefill;
- candidate: prefix/KV reuse;
- context remains 2048;
- batch/uBatch remains 32/32;
- Metal Tensor remains disabled.

Primary workload:
- growing multi-turn history at ~600, ~1000, ~1500, ~1900 prompt tokens.

Success requires:
- exact output equivalence on deterministic workloads;
- material TTFT reduction for reused history;
- no cross-request/cross-conversation contamination;
- explicit isolation for changed system prompt / unrelated conversation;
- no Vision regression;
- no cold-start regression.

### After reuse is proven
Build 77 or a later controlled capacity build:
- 2048 → 3072 → 4096;
- near-capacity latency measured with and without reuse;
- memory/Metal/jetsam gate;
- only then consider 6144/8192.

## Product target

Minimum practical target:
- 4096 context with safe text prefix reuse.

Stretch target:
- 8192 context if memory and near-capacity latency remain acceptable.
