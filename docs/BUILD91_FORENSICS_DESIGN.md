# Build 91 — Long-Context Execution Forensics (P0)

## Baseline and constraints
- Base: `lab-v1-rc1-26-build90-certification-p1`, commit `ef50b2573198c191b04e009f320cb4b3def0773f`.
- This branch is observational only: no llama.cpp or Prism alteration, no KV/cache policy changes, no scheduling, cancellation or performance “fixes”.
- Incident: after twelve RC1 API successes including 1/2/3-image requests and post-vision text, the approximate 6K request timed out (~55.7s), and a 15s health probe timed out. Neither proves native crash or deadlock; original health calls may themselves be slow.

## Inspected call chain (as far as source inspection proves)
1. `LocalOpenAIServer.process` handles incoming HTTP; `/health` is an HTTP-level status response.
2. Chat request authorization/parsing and model-id validation occur before creating Swift `Task`.
3. Stream and non-stream tasks await an injected `handler(payload, onDelta)` and emit success/error completions.
4. Product-side handler in `ProductionView.swift` enters `BonsaiEngine`; the engine creates llama.cpp context and performs text or two-phase multimodal inference.
5. Native llama.cpp/Prism batch-level execution must be audited before claiming batch progress or cancellation propagation. P0 does **not** observe it.

## Implemented P0
- Bearer-protected `GET /debug/execution`: no model computation or await.
- Separate `NSLock`-guarded execution snapshot, decoupled from model runtime.
- Bounded active request metadata per request: run_id, request_id, test_case, phase, monotonic uptime, elapsed time, sequence. Only the last terminal event is retained; active map may contain active request entries.
- Early parsing/admission records a terminal received event, avoiding orphan “busy” leases for requests that are rejected before handler start.
- Both stream and non-stream handler tasks mark entered, completed, or failed. These are **handler-level** phases only.
- Snapshot flags: `observer_only=true`, `native_prefill_progress_available=false`, `cancellation_propagation_verified=false`.
- Authorization is verified before the diagnostic route. API key, raw prompt and response text must never appear in diagnostic snapshot.

## Known gaps / next integration
- P0 does not observe actual prompt tokenization, prefill batch index, Metal workload, memory footprint, native cancellation, disconnect propagation, or process death.
- Thread-safe status only confirms Swift task level; a blocked native handler can remain marked active.
- Request identifiers can collide if distinct clients reuse the same custom header. P1 should use a server-generated internal lease identifier (and preserve supplied correlation ID as metadata), bound active count and history, and reject or namespace collisions.
- Phase timestamps do not prove progress while blocked. Mark `stalled_suspected` only after independent native progress evidence.
- Close/disconnect and app lifecycle instrumentation must be designed and tested separately.
- Build metadata/provenance follows Build90 mechanisms; a real signed-on-device build must be verified independently.

## Next steps (in priority order)
1. Identify actual text prefill loop and llama.cpp batch primitive. Add strictly observational sampling after batch completion, not per token.
2. Track actual token counts and stage transitions via injected request ID, without retaining prompt content.
3. Record safe process footprint / Metal allocation at bounded stage transitions; do not infer OOM without iPadOS jetsam/crash evidence.
4. Add independent low-latency health snapshot and explicit ‘busy’ versus ‘ready-to-infer’ semantics.
5. Develop *separate* controlled cancellation branch only after understanding C/native interruption and cache consistency.
6. Device A/B: short text, same approx-6K prompt with precise token count, post-timeout HTTP health plus execution snapshot, one image, post-vision text. Stop on loss of service.

## Acceptance
- P0 is **source committed**, not yet device-certified.
- Do not report 6K as fixed, cancellation implemented, prefill traced, or a new stable build until actual CI and iPad results verify it.
