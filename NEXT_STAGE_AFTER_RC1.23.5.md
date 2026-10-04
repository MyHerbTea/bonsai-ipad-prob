# NEXT STAGE AFTER RC1.23.5

Start version: **RC1.23.6**
Stage: **API Runtime Lifecycle & Restart Safety**

## Why this stage exists

RC1.23.5 closed with:

**NO SAFE WIN FOUND**

- batched suffix-prefill optimization was rejected by profiling;
- 256-context Dynamic Context was rejected by controlled A/B;
- the RC1.23.4 Build 46 frozen runtime remains the production baseline.

The Build 48 test also revealed a more important correctness risk:
the app crashed at least once during repeated API stop/context-switch/start
cycles.

The recovery breadcrumb reported:

```text
Engine stage: TWOPHASE_VISION_20_FIRST_TOKEN
```

A code audit found a plausible lifecycle race:

- Stop API calls `apiServer.stop()`;
- teardown then runs asynchronously through
  `Task { await engine.unloadAll() }`;
- the UI can become restartable before that teardown is explicitly joined;
- `LocalOpenAIServer.stop()` cancels the listener but does not track/cancel
  already-created request handler Tasks.

This is not yet proven as the crash root cause. RC1.23.6 must establish that
root cause before changing architecture.

## Authoritative production parent

Use the RC1.23.4 Build 46 frozen executable as the correctness baseline:

`4c0a453339350c0c915578a46a15d4235ab0ff99`

Keep frozen:

- API context=512;
- Accelerated default;
- Safe fallback;
- batch=8;
- ubatch=8;
- n_seq_max=1;
- C2-B same-sequence checkpoint/restore;
- Vision Prefix KV reuse;
- EOG/length provenance;
- Build 46 telemetry semantics;
- UTF-8-safe API behavior.

Build 47/48 profiling fields may be retained as observability if useful, but
their experimental behavior must not become the production baseline.

## Phase A — Reproduce and isolate

Before implementing a fix, test lifecycle behavior under the frozen 512 context.

Required control:

```text
512 only
stop API
start API
seed request
warm request
repeat
```

Do not switch context sizes.

The control must distinguish:

1. generic repeated restart instability;
2. context-switch-specific instability;
3. stopping while an API request is still active;
4. starting while a previous unload is still pending.

Collect:

- persisted crash breadcrumb;
- engine stage;
- API server state;
- teardown/start timestamps;
- whether an active request existed at Stop;
- whether `unloadAll()` had completed before Start became available.

## Phase B — Lifecycle ownership design

Only after Phase A evidence identifies a race should production code change.

The desired state machine should make lifecycle ownership explicit:

```text
STOPPED
  -> STARTING
  -> RUNNING
  -> STOPPING
  -> STOPPED
```

Rules:

- Start is disabled in STARTING/STOPPING.
- Stop transitions to STOPPING immediately.
- teardown is awaited.
- engine unload completion is observable.
- new Start cannot race a previous unload.
- in-flight requests are either awaited or cancelled before engine memory is
  released.
- listener shutdown alone is not treated as request-task shutdown.

## Candidate implementation constraints

Do not:

- change model/runtime performance settings;
- change C2-B;
- change n_seq_max;
- change sampler or generation semantics;
- reduce output budgets;
- reintroduce Dynamic Context.

Prefer the smallest lifecycle fix that establishes deterministic ownership.

## Acceptance

At minimum, a candidate must pass:

- repeated 512-only stop/start cycles;
- seed + warm request after each restart;
- no crash;
- no stale request handler using an unloaded engine;
- C2-B still works within each fresh session;
- memory does not grow monotonically;
- text and Vision API remain correct.

After lifecycle safety is certified, performance work may resume.

## Secondary compatibility backlog

ChatBox mobile streaming compatibility is a separate API-client issue and should
not be mixed into the lifecycle fix unless evidence proves the same root cause.

It can be investigated after runtime restart safety is stable.
