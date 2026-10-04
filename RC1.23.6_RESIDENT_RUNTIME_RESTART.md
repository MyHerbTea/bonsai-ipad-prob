# RC1.23.6 Build 52 — Resident Runtime Restart

Status: **TRUE-DEVICE ROOT-CAUSE CANDIDATE**

Parent:
- Build 50 one-click restart runner: true-device INTERRUPTED
- Build 51 recovery/export fix: CI PASS
- production behavior remains RC1.23.4 Build 46 FROZEN

## Build 50 evidence

The recovered Build 50 archive proves:

- fixed API context was 512;
- runtime profile was Accelerated;
- cycle 1 full-load seed request completed HTTP 200;
- cycle 1 warm request completed HTTP 200 with 115 completion tokens and stop;
- Prefix KV reuse HIT and retained=true on the warm request;
- cycle 1 completed;
- cycle 2 completed the explicit engine unload;
- cycle 2 requested API start;
- the app terminated before api_ready;
- recovered engine stage was MODEL_07_CONTEXT_CREATE_BEGIN.

This isolates the failure to the second same-process full runtime creation path.

## Existing architecture evidence

RC1.21.2 previously recorded the same fatal native boundary:

`MODEL_07_CONTEXT_CREATE_BEGIN`

after a 27B runtime had already existed in the same process.

Build 50 strengthens that evidence because no 256 context switch is involved and
the explicit engine unload had already completed.

## Build 52 hypothesis

Do not recreate the full 27B llama model/context merely to restart the LAN API.

Separate:
- network listener lifecycle;
- resident inference runtime lifecycle.

## Controlled sequence

Build 52 still performs four cycles.

### Cycle 1

```text
stop listener
→ await engine.unloadAll()
→ normal startAPIServer()
→ load frozen 512 / Accelerated runtime
→ seed
→ warm
```

This retains the known clean-process/full-load control.

### Cycles 2–4

```text
restartListenerPreservingHandler()
→ keep same 27B model
→ keep same llama context
→ keep same OpenAI handler closure
→ wait listener ready
→ seed
→ warm
```

No `engine.unloadAll()` and no `llama_init_from_model()` are intentionally
executed during cycles 2–4.

## LocalOpenAIServer change

Build 52 adds:

`restartListenerPreservingHandler(port:)`

The method:
1. retains the currently installed OpenAI request handler closure;
2. stops the Network listener;
3. starts a new listener using that same handler;
4. does not touch BonsaiEngine.

## Frozen behavior

Unchanged:
- API context 512;
- Accelerated runtime;
- batch 8;
- ubatch 8;
- n_seq_max 1;
- C2-B;
- Vision Prefix KV reuse;
- max completion tokens 128;
- stream=false;
- reasoning_effort=none;
- same controlled image/prompt;
- one-file crash-resilient recorder;
- Build 51 disk-backed recovery/export.

The rejected 256 experiment remains removed.

## Acceptance

Strong PASS:
- all 4 cycles complete;
- cycles 2–4 report restart_mode=listener_restart_resident_runtime;
- all seed/warm calls are HTTP 200;
- no MODEL_07_CONTEXT_CREATE_BEGIN transition occurs during cycles 2–4;
- C2-B remains healthy inside each resident session;
- no crash;
- no unacceptable monotonic memory growth.

If PASS, the next production change should separate "Stop API listener" from
"Release model/runtime" instead of coupling both actions.

If FAIL before a request begins, inspect the listener/connection lifecycle.

If FAIL during seed/warm with the resident context preserved, investigate
request cleanup/state reuse instead of model/context reconstruction.
