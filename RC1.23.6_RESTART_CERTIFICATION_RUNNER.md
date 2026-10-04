# RC1.23.6 Build 50 — One-Click Restart Certification Runner

Status: **PHASE B TRUE-DEVICE CANDIDATE**

Parent:
- Build 49 Certification Recorder: CI PASS
- RC1.23.5: NO SAFE WIN FOUND
- production behavior remains RC1.23.4 Build 46 FROZEN

## User workflow

Build 50 removes the previous manual multi-snapshot workflow.

The intended user procedure is:

```text
1. Install Build 50
2. Select:
   - main 27B model
   - Vision Tower safetensors
   - one test image
3. Tap:
   Run Restart Certification
4. Leave the app in foreground until it completes or crashes
5. Tap:
   Share Result
6. Send the single BONSAI-RUN-*.json
```

No per-cycle copy/paste is required.

The runner does not require mmproj.

## Frozen test configuration

The runner forces the certified production baseline:

- API runtime profile: Accelerated
- API context: 512
- API batch: 8
- API ubatch: 8
- n_seq_max: 1
- Vision Prefix KV reuse: enabled
- max completion tokens: 128
- stream: false
- reasoning effort: none

Controlled prompt:

`Describe the person, the dog, and the background in this image using concise bullet points.`

The rejected 256-context experiment is not exposed.

## Automated sequence

The runner performs four cycles.

Each cycle is:

```text
cycle_started
    ↓
api_stop_requested
    ↓
apiServer.stop()
    ↓
engine_unload_started
    ↓
await engine.unloadAll()
    ↓
engine_unload_finished
    ↓
api_start_requested
    ↓
reuse product startAPIServer()
    ↓
wait until API ready
    ↓
api_ready
    ↓
seed_request_started
    ↓
POST 127.0.0.1:8080/v1/chat/completions
    ↓
seed_request_finished
    ↓
warm_request_started
    ↓
POST 127.0.0.1:8080/v1/chat/completions
    ↓
warm_request_finished
    ↓
automatic diagnostic snapshot
    ↓
cycle_completed
```

The requests use the actual local OpenAI-compatible server path instead of
calling generation code directly.

## Why teardown is awaited

The Build 48 manual test exposed a plausible stop/start lifecycle race:

- Stop made the server appear stopped immediately;
- engine teardown continued asynchronously;
- the user could manually restart before teardown was explicitly joined.

Build 50 intentionally uses:

```text
apiServer.stop()
await engine.unloadAll()
startAPIServer()
```

inside the controlled runner.

This does not yet modify the normal Stop API button. It is an experiment to
answer:

> Does repeated 512-only restart remain stable when teardown is explicitly
> awaited before the next start?

If Build 50 passes all cycles, that is evidence supporting the lifecycle-race
hypothesis and informs the production lifecycle fix.

If Build 50 still crashes, the problem is broader than the manual stop/start
overlap window.

## Automatic evidence

The recorder persists ordered events after every state transition.

For each seed/warm request, the archive records:

- cycle number;
- HTTP status;
- external elapsed time;
- completion tokens;
- finish reason.

After every scored warm request it embeds the full redacted Diagnostic Snapshot,
which already contains:

- request ordinal;
- TTFT;
- prefill;
- suffix prefill;
- suffix batching;
- decode time;
- decode TPS;
- C2-B HIT/retained;
- memory;
- Metal allocation;
- public thermal state;
- persisted stages.

The user does not need to extract these fields manually.

## Crash behavior

The active archive is atomically persisted after every event/snapshot.

If the app crashes during any cycle, the next launch automatically converts the
unfinished active run to:

`status = interrupted`

and makes that recovered `BONSAI-RUN-*.json` shareable.

The last recorded event identifies the phase reached before termination, while
the persisted engine/stage files provide the native inference breadcrumb.

## Result interpretation

### PASS candidate

A clean run should show:

- 4/4 cycles completed;
- seed and warm HTTP 200 each cycle;
- 115-token natural EOG for the controlled prompt, unless a new model-output
  regression is discovered;
- warm Prefix KV HIT + retained=true;
- no crash;
- no monotonically growing memory footprint;
- no stale context/runtime state.

### FAIL / interrupted candidate

Any of the following is sufficient to stop acceptance:

- app crash;
- archive status interrupted;
- API restart timeout;
- non-200 seed/warm request;
- inference failure;
- stale request/runtime state;
- meaningful monotonic resource growth.

## Next gate

Do not implement the production lifecycle fix until Build 50 true-device
evidence is available.

The next code decision must be based on the single-file archive:

- if awaited teardown stabilizes repeated restart, promote explicit lifecycle
  state/awaited teardown into the normal API controls;
- if instability remains, continue root-cause isolation before changing
  production lifecycle ownership.
