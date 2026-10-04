# RC1.23.5 Phase B — Dynamic Context True-Device A/B Evidence

Status: **FAIL — 256 CONTEXT REJECTED**

Parent candidate:
- RC1.23.5 Build 48
- source head: `47ac13d0313daaa5bbe42e63dc8978ffe28d33aa`
- CI #41 / run `37211204450` / SUCCESS
- artifact: `BonsaiLab-iPad-v1-RC1.23.5-Build48-Dynamic-Context-AB-Candidate`
- artifact id: `11306576961`

Device:
- iPad Pro M5
- iPadOS 27.0.1
- physical memory: 11524 MiB
- runtime: Accelerated
- batch=8
- ubatch=8
- n_seq_max=1
- C2-B enabled
- output budget=128

## A/B method

The device test alternated context sizes:

```text
PAIR1_512
PAIR1_256
PAIR2_512
PAIR2_256
PAIR3_512
PAIR3_256
PAIR4_512
PAIR4_256
```

For each profile switch:
1. API runtime was stopped.
2. 512 Baseline or 256 Experimental was selected.
3. API runtime was restarted.
4. One seed request established the Prefix KV state.
5. One scored warm-HIT request was measured.

Controlled prompt:

`Describe the person, the dog, and the background in this image using concise bullet points.`

Every scored request:
- completion tokens: 115
- finish reason: stop
- natural EOG
- Prefix KV reuse: HIT
- prefix retained: true
- suffix tokens: 29
- suffix decode calls: 4
- batch utilization: 0.9062

## External E2E scored results

| Pair | 512 Baseline | 256 Experimental | 256 - 512 | Relative |
|---|---:|---:|---:|---:|
| 1 | 12319.8 ms | 12437.4 ms | +117.6 ms | +0.95% |
| 2 | 12396.3 ms | 12548.5 ms | +152.2 ms | +1.23% |
| 3 | 13672.7 ms | 15669.8 ms | +1997.1 ms | +14.61% |
| 4 | 18555.7 ms | 20145.4 ms | +1589.7 ms | +8.57% |

Summary:

| Metric | 512 | 256 |
|---|---:|---:|
| mean E2E | 14236.1 ms | 15200.3 ms |
| median E2E | 13034.5 ms | 14109.2 ms |

256 was slower in **all four paired comparisons**.

Mean penalty:

```text
+964.2 ms
+6.77%
```

Median penalty:

```text
+1074.7 ms
+8.24%
```

## Internal telemetry evidence

Three complete scored 512/256 diagnostic pairs were captured with matching
runtime context.

### Median internal metrics

| Metric | 512 | 256 |
|---|---:|---:|
| total_ms | 13309.447 | 15366.760 |
| ttft_ms | 2973.079 | 2996.058 |
| suffix_prefill_ms | 2509.358 | 2534.896 |
| suffix ms/decode call | 627.339 | 633.724 |
| decode_ms | 10459.710 | 12402.299 |
| decode TPS | 10.995 | 9.272 |
| available_mib | 4473 | 4481 |
| phys_footprint_mib | 646 | 638 |
| metal_allocated_mib | 6109 | 6092 |

Interpretation:

1. 256 did **not** produce a repeatable TTFT improvement.
2. 256 did **not** produce a repeatable suffix-prefill improvement.
3. The resource saving was tiny relative to the model footprint:
   - about 17 MiB less Metal allocation;
   - small physical-footprint differences.
4. The later 256 samples were materially slower in decode throughput, consistent
   with the previously observed sustained-performance-state drift rather than a
   context-size speedup.

## Stability failure observed

During the alternating 256 -> 512 switching sequence, the app crashed at least
once.

After relaunch, the recovery diagnostic reported:

```text
status=检测到上次运行未完成
Engine 阶段=TWOPHASE_VISION_20_FIRST_TOKEN
```

This is a blocking guardrail failure for the experimental candidate.

The evidence does not prove that `n_ctx=256` itself directly caused the crash.
The crash occurred in a workflow that repeatedly stopped, unloaded, reloaded,
and restarted the API runtime while changing context size.

A code audit identified a lifecycle risk that requires separate investigation:

- the Stop API button calls `apiServer.stop()`;
- it then launches `Task { await engine.unloadAll() }`;
- the UI becomes restartable before that async unload is explicitly joined;
- `LocalOpenAIServer.stop()` cancels the listener but does not own/cancel
  already-created request handler Tasks.

This is a plausible restart/lifecycle race window, not a proven crash root cause.

## Diagnostic note

One snapshot captured while the API was stopped showed:

```text
requested=512
active=256
api_context=512
```

This was a transition snapshot, not a scored request. When the server is stopped,
the current diagnostic presentation prefers the requested profile for
`api_context`, while the persisted active context still records the previous
runtime. Do not use transition snapshots for A/B scoring.

Also, the legacy `[API PREFLIGHT]` block still reports
`effective_ctx=512` even for a confirmed active 256 runtime. That field belongs
to the older Swift-Vision preflight diagnostic and is not authoritative for the
Build 48 runtime context. The authoritative Build 48 fields are:

- `api_context`
- `rc1235_api_context_requested`
- `rc1235_api_context_active`
- `rc1235_api_context_profile`

when the API is running.

## Phase B decision

### Candidate B — 256 / Dynamic Context proof

**REJECTED.**

Reasons:

1. 256 was slower in all four scored paired E2E comparisons.
2. Median E2E was about 8.2% worse.
3. TTFT and suffix-prefill did not show a repeatable improvement.
4. Memory savings were negligible for this workload.
5. A crash occurred during the repeated context-switch/restart experiment.

No automatic 256/384/512 admission policy should be implemented from this
evidence.

## Production decision

Keep the production runtime behavior at the RC1.23.4 Build 46 frozen baseline:

- API context=512
- Accelerated runtime
- batch=8
- ubatch=8
- n_seq_max=1
- C2-B unchanged

Build 48 remains an experimental artifact only.
