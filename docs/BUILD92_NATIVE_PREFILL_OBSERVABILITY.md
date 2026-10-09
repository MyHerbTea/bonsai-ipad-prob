# Build 92 P0 — Native Text Prefill Forensics

Baseline: Build91 certified source `026edf5875ff03dbcffd821db67e913b98e342bc`.

## Objective

Diagnose the 120s long-input timeout without changing Metal, llama.cpp, KV formats, model loading, batch size, or cancellation behavior.

## Implemented instrumentation

- Request elapsed duration is computed at snapshot time using process uptime, not cached at the last transition.
- `BonsaiEngine.evalTextTokens` emits `decode_begin` immediately before `llama_decode` and `decode_end` after its return.
- Progress callback carries remaining input token count after KV reuse, successfully completed token count, batch index, and observed wall-clock duration in milliseconds.
- `ProductionView` links native events to the existing OpenAI certification request ID.
- `LocalOpenAIServer` stores only metadata behind its existing forensics lock. No prompt content or API key is stored.
- `GET /debug/execution` calculates `current_batch_elapsed_ms` while a batch is in flight and `last_progress_age_ms` from the last native update.

## Limitations / unresolved

- P0 does not turn on native cancellation; client timeout and TCP disconnect may remain unobserved.
- Status is text-prefill-specific; MTMD and image prefill are not instrumented.
- Inference is actor-isolated. Observer callback is synchronous and must not await, block on the network, or acquire an inference lock.
- There is no proof of a Metal deadlock. A lengthy in-flight batch is evidence of duration, not failure.
- Baseline and candidate must be tested with the same model and runtime configuration. The UI may report 32K capacity but actual prompt token count is observed from tokenizer inside engine.
- The previously built Build91 app remains the rollback path.

## Acceptance gates

1. Actual macOS GitHub Actions iOS compilation and unsigned IPA packaging.
2. Compilation and runtime tests for correlation ID, live elapsed time, in-flight and completed batches, and no request leakage.
3. Short text baseline, then one long text with independently polled execution snapshots.
4. Build92 native schema cannot be claimed certified until physical iPad evidence is collected.

## Known design constraints

This is an observation-only experimental branch. Do not infer cancellation from client timeout and do not change llama.cpp resource-release sequencing.
