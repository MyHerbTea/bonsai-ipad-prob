# RC1.26 Phase 2I0 — Aggressive Text KV / Context Audit

Status: **SOURCE AUDIT COMPLETE / BUILD 76 DESIGN READY**

Stable parent:
- Build 75 certified product commit: `c09b2e09706dd0c0391b7a15727da57e0f17d425`
- stable checkpoint remains immutable
- 2048 context
- 32×32 prefill
- Full / Accelerated
- Metal Tensor disabled

## Why this stage exists

Phase 2H0 proved that decode is already usable (~13 tok/s) while long-history prefill is the dominant latency:
- 628 prompt tokens: 11.74 s prefill
- 1089: 21.24 s
- 1630: 38.72 s
- 1898: 46.22 s

The highest-value optimization is therefore to avoid re-prefilling unchanged text history.

## Source findings

### Current text path
`BonsaiEngine.generateText`:
1. builds/tokenizes the complete submitted prompt/history;
2. calls `llama_memory_clear(llama_get_memory(context), true)`;
3. evaluates every prompt token again;
4. generates token-by-token.

This guarantees growing OpenAI conversation history pays the full prefill cost every request.

### Existing proven on-device state mechanism
The Vision bridge already uses:
- `llama_state_seq_get_size_ext`
- `llama_state_seq_get_data_ext`
- `llama_state_seq_set_data_ext`
- `LLAMA_STATE_SEQ_FLAGS_ON_DEVICE`

The current bridge explicitly documents that the host vector contains only sequence-state metadata while KV tensors are snapshotted into Prism-managed backend buffers.

This mechanism is already used by `BonsaiRetainVisionPrefixKV` and restore logic on the same resident llama context.

### Tail editing API
The pinned llama API also exposes sequence-memory operations such as:
- `llama_memory_seq_rm`
- `llama_memory_seq_cp`

This enables a more aggressive text path than full snapshot/restore:
- preserve current resident KV;
- tokenize the next complete prompt;
- compute token-level longest common prefix (LCP) against the token stream represented by resident KV;
- remove KV positions from LCP onward;
- prefill only the new suffix;
- continue generation.

If tail removal is unsupported/fails, fall back to the proven full-clear/full-prefill Build 75 path.

## Build 76 — M5 Extreme Context Lab

Build 76 is an experimental lab build, not an automatic production promotion.

### Arm A — frozen baseline
- 2048 context
- text reuse OFF
- 32×32
- current Build 75 semantics

### Arm B — live Text KV tail reuse
- 2048 context
- preserve resident text KV after a successful text request
- cache exact token IDs corresponding to resident positions
- next request computes exact token LCP
- trim resident KV tail after LCP
- prefill only suffix
- deterministic fallback to Arm A on any uncertainty

### Arm C — on-device sequence snapshot fallback
Use the already-proven `LLAMA_STATE_SEQ_FLAGS_ON_DEVICE` snapshot/restore mechanism when live-tail reuse cannot be safely continued.

### Capacity ladder in the same lab build
Expose experimental:
- 2048
- 3072
- 4096
- 6144
- 8192

Run capacity only after Arm B correctness passes at 2048.

## Aggressive policy

The lab is allowed to push M5 hard:
- retain the 27B mmap model;
- keep the active llama context resident;
- keep reusable KV on Metal/backend memory;
- preserve 32×32 prefill;
- Full acceleration stays ON;
- no artificial cooldown;
- no conservative 512/1024 fallback unless admission safety requires it;
- probe 4096 immediately after reuse certification;
- continue to 6144 and 8192 while memory/Metal/jetsam gates remain healthy.

## Safety / correctness invariants

Aggressive performance does not relax correctness.

Reuse is allowed only when:
- same resident model/context generation;
- same runtime profile/context size;
- exact token equality for every reused position;
- sequence positions and cached token count agree;
- no preceding request failed;
- no Vision request has invalidated text KV;
- no context/profile switch occurred.

Any mismatch:
- clear working memory;
- discard text cache metadata;
- run current Build 75 full-prefill path.

## Required contamination tests

Must prove no leakage across:
- unrelated conversation after a previous cached conversation;
- changed system prompt;
- changed first user message;
- identical beginning but divergent middle;
- streaming vs non-streaming;
- cancelled/failed request followed by new request;
- text → Vision → text;
- API stop/resume;
- context/profile switch.

## Performance target

At 2048:
- repeated/growing history should make TTFT track **new suffix length**, not total history length.

Representative target:
- a 1500-token existing history + ~100-token new turn should no longer pay ~39–47 s prefill;
- target is single-digit-second TTFT, with stretch goal near the cost of only the new suffix.

Capacity target:
- minimum production-worthy: 4096 + safe reuse;
- stretch: 8192 + safe reuse;
- reject any context tier that creates unacceptable cold-start, jetsam, Vision regression, or near-capacity latency.

## Build discipline

Build 75 remains the rollback checkpoint.
Build 76 is permitted to be aggressive because every candidate has:
- explicit feature latch,
- baseline arm,
- telemetry,
- exact fallback,
- evidence gates.
