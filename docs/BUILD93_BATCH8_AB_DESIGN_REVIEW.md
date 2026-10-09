# Build 93 P0 — Source-grounded 32K Prefill Batch8 A/B Design

Status: **DESIGN REVIEW ONLY**, NOT CERTIFIED and NOT YET DEPLOYABLE.
Baseline: Build92 `afdaafc5fa4aa4ffb6cf4723128f214337d7fe97` (iOS Actions success #37915551429).

## Evidence

- Build92 32K test: 7300 prompt tokens, 884 completed after ~133s; 4-token llama_decode batches; ~6–7 prefill tokens/s. No completed TTFT at 7300.
- `ProductionView.applyBuild82LongContextPolicy` caps **both** batch and ubatch to 4 for context >= 32768. This applies after Phase2D/E/F launch latches; the context-init path sets n_batch/n_ubatch from applied config.
- Existing code comments explicitly tie the 32K policy to Build81 model/context initialization failure and minimizing split Metal/CPU graphs. **This does not prove batch8 unsafe or safe.**
- `BonsaiEngine.evalTextTokens` uses `min(appliedRuntime.batch, remaining)` and has Build92 begin/end batch snapshots.
- `BonsaiEngine.generateText` has exact-token KV prefix reuse; equal prompts run back-to-back are not fair cold-prefill comparisons.
- For context >=16K context construction chooses `GGML_TYPE_Q4_0` for both K/V. Actual KV footprint must be measured; using n_embd instead of KV head dimensions is incorrect.
- Existing `RC126APIStartupLifecycle` records stages / prior incomplete startups. Reuse this concept instead of adding uncontrolled crash markers.

## AI B review: accepted

- Candidate only 8/8, baseline 4/4, isolate any changes to context shape; retain 99 GPU layers, Q4 KV, flash attention, and offload settings.
- Need context reconstruction to change n_batch/n_ubatch.
- Do not enable 8/8 as stable default until real-device evidence.
- Abort on crash, Metal/llama error, mismatched effective context, or any regression in basic API/vision capability.

## AI B review: rejected / not proven

- The report's estimated 640KB memory delta ignores real backend graph/workspaces. No bounded memory risk can be asserted without telemetry.
- Predicted ~2x throughput is an experiment hypothesis, not an expected guarantee; hypothetical 70ms/batch contradicts observed ~0.6s/batch average.
- Baseline never completed 7300 tokens; therefore a claimed 40% reduction in *measured* 7300 TTFT is invalid.
- An unclean marker cannot identify Jetsam specifically: force quit, OS reclamation and native crash are all possibilities.
- `testedSuccessfully=false` must not by itself force fallback on every next launch; trial, shutdown, failure, and fallback semantics require a coherent state machine.
- There is no mathematical proof that batch8 failure implies batch16 failure.
- A single 7300-token run at >=10 tokens/s is >12 minutes prefill alone; do not require repeated long tests by default.
- Increased output batch size does not change 32K KV capacity at fixed context in a simple proportional way; actual graph memory must be measured.

## P0 bounded experiment

1. Establish 4/4 baseline metrics from existing Build92 evidence (not full-run TTFT) plus new reproducible 256/1024 prompts as needed.
2. Candidate 8/8: verify active AND engine-created batch=8/ubatch=8 via diagnostics, not UI advertised value alone.
3. Preflight 256 tokens, then 1024 tokens; terminate if startup fails, decode returns nonzero, native progress stalls, or memory pressure indicates risk.
4. Continue to longer input ONLY if success, observable > baseline throughput, sufficient headroom, and a defined time budget. 7300 input optional single controlled comparison.
5. Maintain 4/4 as fallback and keep Build92 IPA as rollback. Changing config requires context rebuild while no inference is active.
6. Do not automatically relaunch an iPadOS app (OS lifecycle can prevent it); mark failed attempt and choose 4/4 on the **next** authorized start.
7. Archive only metadata, timestamps, actual token counts, prior/current batch config, crash-stage evidence, and runtime memory; no API key or prompts.

## Outcome triage

- PASS: actual 8/8 runtime confirmed; short and medium successful; real speedup and no stability regression in tested envelope.
- FAIL: context/decoder failure, crash, or unsafe pressure; next startup must use 4/4.
- INCONCLUSIVE: missing native progress, no comparable cold-prefix A/B, incomplete run, or uncertainty on thermal/memory envelope.

Never call candidate production-Stable on the strength of a CI build or a single short test.

## Development gates

- Separate branch and unchanged Build92 baseline.
- Actual iOS CI compilation + unsigned IPA generation.
- Behavior tests for candidate/fallback selection, restart after aborted trial, runtime effective shape, API identity, no inference overlap, bounded logging, and unchanged Build91/92 contracts.
- Real-device stepwise testing only after CI passes. Keep user's manual work to installing IPA and running one prevalidated Windows driver.
