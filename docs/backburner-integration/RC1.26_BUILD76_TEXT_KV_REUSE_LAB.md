# RC1.26 Build 76 — M5 Extreme Text KV Reuse Lab

Status: **IMPLEMENTATION CANDIDATE — DEVICE CERTIFICATION REQUIRED**

Parent:
- Build 75 certified product commit: `c09b2e09706dd0c0391b7a15727da57e0f17d425`
- Build 75 remains the rollback checkpoint.

Frozen from Build 75:
- context = 2048
- batch/uBatch = 32/32
- Full / Accelerated runtime
- Metal Tensor disabled
- OpenAI API semantics
- Vision path and 1–3 image behavior
- staged API cold-start guard

## Build 76 change

Text requests no longer unconditionally clear and re-prefill the full prompt when an exact reusable prefix exists.

After a successful text request:
1. generation completes normally;
2. generated-tail KV is removed from sequence 0;
3. the complete prompt token ledger is retained;
4. resident llama context remains alive.

On the next text request:
1. tokenize the complete new prompt exactly as before;
2. calculate token-level longest common prefix against the retained prompt;
3. require at least 16 exact reusable tokens;
4. trim resident sequence 0 from the reuse boundary onward;
5. prefill only the changed suffix;
6. re-decode at least the final prompt token so sampler logits always belong to the current request.

Any mismatch, unsupported trim, context/profile change, Vision request, runtime unload, or request failure invalidates the text cache and falls back to the frozen Build 75 full-clear/full-prefill path.

## Observability

`/debug/prefill` exposes:
- `text_kv_reuse.enabled`
- `text_kv_reuse.hit`
- `text_kv_reuse.lcp_tokens`
- `text_kv_reuse.reused_tokens`
- `text_kv_reuse.suffix_tokens`
- `text_kv_reuse.reason`

Implementation ID:
`rc126.build76.text-kv-tail-reuse.v1`

## First device gate

The included runner:
`tools/rc126_build76_text_kv_reuse_ab.ps1`

uses a fixed long system prefix and verifies:
- first request = cold/full prefill;
- second request = reuse hit;
- at least 500 tokens reused;
- >=50% prefill reduction;
- growing history still reuses;
- unrelated conversation does not reuse;
- exact deterministic codewords remain correct.

## Promotion rule

Build 76 is not stable until real-device evidence proves correctness and substantial TTFT reduction.

Only after this gate passes may the capacity ladder begin:
3072 → 4096 → 6144 → 8192.
