# RC1.26 Build99 — Experimental Exact Append-Only Prefix Acceleration

Status: **SOURCE IMPLEMENTED / NOT DEVICE CERTIFIED**. Do not promote to Stable on a compilation success or theoretical speedup alone.

## Frozen control and goal
- Stable functional baseline: Build97, commit `f88ed20ac320671c9308bb7c6b84a0288f08ead6`.
- Pinned engine: PrismML llama.cpp `adfffbe41b2cabcd51fff326ab045662265062bb` unchanged.
- Build98 M5 FA-vec NE1/2/4 negative exploration remains closed; no kernel update.
- First priority: reduce user-visible inference latency, beginning with *unnecessary repeated Prefill in multi-turn text sessions*.
- Second priority, measured independently: *unavoidable first-pass Prefill* with 32K context, Batch 8/16.
- Preserve Vision, API, generation accuracy, 32K memory safety, and long-output usability.

## Why not simply enlarge `n_rs_seq`
The hybrid GDN + full-attention memory must be treated as one inseparable state. Prism  `llama_memory_hybrid::seq_rm()` first asks recurrent state to undo the requested range. Default `n_rs_seq=0` rejects ordinary generated-tail truncation. The usual retry-to-clear is safe but pays Prefill again.

Snapshot buffer rows scale as `mem_size * (1 + n_rs_seq)`. A constant `n_rs_seq=4` means a bounded token-backtrack capability, **not** four conversation turns. We do not change `n_rs_seq` or recurrent memory allocation in Build99.

## Exact append-only experiment
The candidate retains **all** tokens physically decoded in a single successful text response: full prompt token ids + *actual generated token ids* after successful `llama_decode()` for each token. No end-of-request trim is attempted.

On next text request, reuse is legal only if all these hold:
1. same resident llama context and no model/profile/Vision invalidation;
2. resident ledger contains at least 16 tokens;
3. new prompt has a **strictly longer** token sequence;
4. new prompt token IDs **begin with every previously decoded token ID** (not merely matching text);
5. only the new token suffix is passed to `llama_decode`, at absolute positions beginning exactly after the resident ledger.

Any failed condition causes full `llama_memory_clear` and cold Prefill. No GDN partial rollback. A failed request also clears resident state. An opt-in candidate is one process launch only and automatically reverts to OFF on the next full launch.

**Important feasibility caveat:** Qwen ChatML may retokenize previously generated text plus structural delimiters differently. The candidate may therefore show `append_only_no_exact_extension` for all realistic turns. Such a result is a valid evidence-driven **NO-GO**, not license to weaken exact prefix checks.

## Build99 modes
- `OFF` (default): entire frozen Build97 logic, including legacy tail-trim then clear-on-unsupported; no experimental generated-token capture.
- `APPEND`: token-id ledger and strict append-only continuation on text API paths only, with local-only next-launch selector. Never change arm through API.
- Read-only authenticated `GET /debug/prefill`: `build99_append_only` process state, resident count, and original `text_kv_reuse.hit/reused_tokens/reason`.
- `tools/rc126_build99_append_only_contract_tests.py` verifies conservative guard, OFF mode invariants, and failure cleanup. Offline source tests do not verify tokenizer parity or model output.
- `tools/rc126_build99_multiturn_prefix_probe.ps1`: two-turn OpenAI API test using existing diagnostics, no hardcoded credentials, saves reproducible JSON with hashed outputs.

## Evidence and promotion
1. CI source and Xcode build pass with the exact pinned Prism.
2. iPad OFF comparison: initial and follow-up prompt token counts, cold Prefill, decode, output correctness, 32K context, resident memory, thermal state.
3. iPad APPEND: same prompts in a fresh process, confirm *actual* `text_kv_reuse.hit=true`, reason `append_only_exact_extension`, positive reused tokens, and significantly shorter second-turn Prefill.
4. Compare output content under deterministic decoding; compare actual prompt and output hashes and repeated followups, not only throughput.
5. Negative tests: unrelated user prompt, changed system prompt, altered assistant turn, text after Vision, model/context switch, cancelled/error path, max-output truncation; all must reset and never reuse mismatched state.
6. If no strict prefix hits or correctness differs, stop Build99 and revert to Build97. Do **not** open GDN snapshots by guesswork.

## Independent first-prefill path
Existing Build94 policy at 32K still caps normal batch/uBatch at 8/8; `CANDIDATE16` permits 16/16 after explicit guarded scheduling and a certified baseline. Previous Phase2D/2E/2F parameters do not override this final cap. No unverified 32/32 context profile should be promoted. Measure Native Batch time distribution and Prefill tokens/s to attribute gains.

## Claims that must not be made
- No guaranteed 90% multi-turn speedup or always-applicable prefix matching.
- No 'n_rs_seq=4 supports 4 conversations'.
- No claim GDN can safely evict oldest tokens by merely trimming Attention KV.
- No claim that 7 tok/s is the global Decode ceiling (long/short context conditions differ).
- No claim that a Build99 IPA is stable until device A/B numerical and crash regression pass.
