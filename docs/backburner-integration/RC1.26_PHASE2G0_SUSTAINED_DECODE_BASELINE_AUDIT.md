# RC1.26 Phase 2G0 — Sustained Decode Baseline Audit

Status: **MEASURE FIRST / NO PRODUCT CHANGE**

Parent checkpoint:
- Build 75 device-certified binary commit: `c09b2e09706dd0c0391b7a15727da57e0f17d425`
- stable evidence/docs head before this audit: `8c3ff5b3141b8c53ecc58961d489b90622a48ea1`
- runtime shape: 32×32
- context: 2048
- Metal Tensor disabled

## Why Phase 2G0 exists

Builds 72–74 used a deterministic prefill benchmark whose answer was a single token (`OK`).
That workload is excellent for:
- prompt prefill,
- first-token latency,
- shape correctness,
- deterministic A/B isolation.

It is not a valid sustained-decode throughput benchmark because completion length is one token.

Therefore the next performance stage must establish a long-output baseline before changing decode behavior.

## Source audit

Current text generation path:
1. tokenize prompt;
2. prefill prompt through `evalTextTokens`;
3. enter `decodeGeneratedTokens`;
4. for every output token:
   - `llama_sampler_sample`;
   - EOG check;
   - token-to-piece conversion / UTF-8 assembly;
   - optional streaming callback;
   - allocate `llama_batch_init(1, ...)`;
   - add one token;
   - call `llama_decode`;
   - free the batch.

Runtime:
- GPU layers = 99;
- Flash Attention enabled in accelerated mode;
- KQV offload enabled;
- op offload enabled;
- unified KV enabled for API runtime;
- mmap model load;
- text context uses six CPU threads;
- production batch/uBatch = 32/32.

## Initial interpretation

At the previously observed ~0.8–1.2 seconds for first-token decode, Swift string assembly and one-token batch allocation are unlikely to dominate wall time. The primary suspect is the native one-token `llama_decode` path and its CPU/GPU synchronization.

Do not optimize based on that inference alone.

## Phase 2G0 measurement

Use Build 75 unchanged.

Fixed request:
- text-only;
- context = 2048;
- batch/uBatch = 32/32;
- temperature = 0;
- top_p = 1;
- seed = 424242;
- max_tokens = 128;
- prompt explicitly requests a long numbered sequence so generation should terminate by length rather than EOG.

Run:
- 1 warmup excluded;
- 5 measured requests;
- same app process;
- Bonsai foreground;
- no Vision request between samples.

For every request capture:
- completion tokens;
- finish reason;
- prefill ms;
- decode-to-first-token ms;
- TTFT;
- tokens/s;
- wall time;
- thermal start/end;
- process CPU;
- memory deltas;
- Metal allocation deltas.

## Gate

Only design Build 76 after Phase 2G0.

Candidate branches after evidence:
- If sustained decode is healthy and stable: preserve decode path and optimize a different bottleneck.
- If sustained decode is slow from request 1: profile native one-token decode/offload configuration.
- If decode starts fast then degrades: investigate runtime/Metal state accumulation and recovery matrix.
- If first-token is slow but later tokens are fast: isolate first decode transition rather than steady-state decode.
- If non-native overhead is material: instrument sampler/token-piece/batch allocation before optimizing it.

No speculative decoding, KV redesign, Metal Tensor re-enable, or 64/128 batch experiment is allowed in Phase 2G0.
