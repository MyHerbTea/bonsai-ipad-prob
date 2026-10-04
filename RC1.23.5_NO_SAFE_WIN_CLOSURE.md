# RC1.23.5 — NO SAFE WIN CLOSURE

Status: **CLOSED — NO PRODUCTION OPTIMIZATION ACCEPTED**

## Summary

RC1.23.5 investigated two low-risk approaches to reduce warm multimodal TTFT /
suffix-prefill cost without changing the frozen RC1.23.4 runtime architecture.

### Phase A — Batched suffix prefill

Result: **REJECTED**

True-device profiling showed:

- English concise suffix packing: 29 tokens / 4 x 8-token calls = 90.62%
- Chinese descriptive suffix packing: 22 tokens / 3 x 8-token calls = 91.67%

The batching loop was already densely packed. Substantial latency drift still
occurred while token count, call count, and utilization remained unchanged.

### Phase B — Smaller / Dynamic Context proof

Result: **REJECTED**

Build 48 compared explicit 512 Baseline against 256 Experimental using
alternating true-device pairs.

256 was slower in all four scored pairs.

- 512 mean E2E: 14236.1 ms
- 256 mean E2E: 15200.3 ms
- 512 median E2E: 13034.5 ms
- 256 median E2E: 14109.2 ms

256 also failed the stability guardrail because an app crash was observed during
the repeated stop/switch/start experiment.

## Final RC1.23.5 conclusion

Neither approved optimization hypothesis produced a safe, repeatable win.

Therefore RC1.23.5 closes with the valid outcome defined before experimentation:

> **NO SAFE WIN FOUND**

No production optimization from Build 47 or Build 48 is accepted.

## Production baseline remains unchanged

The authoritative production baseline remains:

**RC1.23.4 Build 46 FROZEN**

Frozen executable source:

`4c0a453339350c0c915578a46a15d4235ab0ff99`

Frozen runtime:

- API context=512
- Accelerated default
- Safe fallback
- batch=8
- ubatch=8
- n_seq_max=1
- C2-B same-sequence ON_DEVICE checkpoint/restore
- Vision Prefix KV reuse enabled
- Build 46 telemetry/finish-reason semantics unchanged

## Experimental artifacts

Build 47 and Build 48 are research artifacts, not new production baselines.

Build 47:
- suffix-prefill profiling instrumentation

Build 48:
- explicit 512-vs-256 context A/B selector

Do not treat the 256 profile as a supported production default.

## New issue discovered

The Build 48 alternating restart test exposed a separate stability concern:
repeated API stop/unload/restart may have a lifecycle race.

Observed recovery breadcrumb after a crash:

```text
Engine stage: TWOPHASE_VISION_20_FIRST_TOKEN
```

Code review shows that the current Stop API path launches
`engine.unloadAll()` asynchronously after `apiServer.stop()`, while the UI can
become restartable before that unload task is explicitly joined.

Also, `LocalOpenAIServer.stop()` cancels the listener but does not own and
cancel already-created request handler Tasks.

This is not yet proven as the crash root cause, but it is now a higher-priority
correctness issue than further TTFT tuning.

## Next engineering priority

Do not continue suffix-prefill or dynamic-context optimization immediately.

Recommended next stage:

**RC1.23.6 — API Runtime Lifecycle & Restart Safety**

Goals:

1. make Stop API an awaited lifecycle transition;
2. prevent Start API until teardown completes;
3. ensure in-flight request handlers cannot outlive the runtime they use;
4. verify repeated stop/start on the frozen 512 context;
5. only after lifecycle stability is certified, return to performance work.

A 512-only repeated restart control must pass before any context-switch
experiment is reconsidered.
