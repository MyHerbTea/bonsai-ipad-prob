# RC1.23.6 Build 53 — Awaited Listener Rebind

Status: **TRUE-DEVICE LISTENER LIFECYCLE CANDIDATE**

Parent:
- Build 50: same-process full runtime recreation crashed at MODEL_07_CONTEXT_CREATE_BEGIN
- Build 51: recovery/export fix
- Build 52: resident-runtime restart avoided the model/context recreation crash, but failed on same-port listener rebinding
- production inference behavior remains RC1.23.4 Build 46 FROZEN

## Build 52 evidence

Build 52 confirmed the resident-runtime direction:
- cycle 1 full-load seed/warm completed successfully;
- cycle 2 kept restart_mode=listener_restart_resident_runtime;
- engine stage remained TWOPHASE_VISION_99_PASS before and after listener restart;
- no MODEL_07_CONTEXT_CREATE_BEGIN recurrence occurred.

The failure moved to the network layer:
- the old listener was cancelled;
- a new listener was created immediately on port 8080;
- the new listener later failed with Network.NWError 48 / Address already in use;
- the runner briefly observed stale isRunning=true and therefore attempted the seed request before the new listener had actually reached a stable ready state.

## Root cause

NWListener.cancel() is asynchronous.

Build 52 performed:

```text
oldListener.cancel()
→ immediately create/bind new listener on 8080
```

This allowed the new bind to race the old listener's actual cancellation.

The old listener's asynchronous state callback could also update shared
`isRunning/status` after a replacement listener had already been created.

## Build 53 fix

Build 53 separates listener shutdown from listener installation.

### restartListenerPreservingHandler

```text
preserve OpenAI handler
→ mark listener generation obsolete
→ set isRunning=false / status=Restarting
→ await old NWListener state == cancelled
→ create new NWListener on 8080
→ install preserved handler
→ wait for new listener ready
```

The 27B model/context is not released during cycles 2–4.

### Listener generation guard

Every installed listener receives a generation token.

State callbacks update:
- isRunning
- status
- lastError

only when their generation is still current.

This prevents an obsolete listener's late cancelled/failed callback from
overwriting the state of the replacement listener.

## Automated evidence

The one-file recorder additionally records:
- listener_cancel_await_begin
- listener_cancel_await_finished
- resident_restart_listener_started
- resident_restart_ready
- seed/warm HTTP results
- diagnostic snapshots

The user still performs one action and returns one BONSAI-RUN JSON file.

## Frozen inference behavior

Unchanged:
- Accelerated
- ctx=512
- batch=8
- ubatch=8
- n_seq_max=1
- C2-B
- Prefix KV reuse
- same controlled image and prompt
- max completion tokens=128
- stream=false
- reasoning_effort=none
- disk-backed recovery/export

The rejected 256 context experiment remains removed.

## Acceptance

PASS requires:
- cycle 1 full runtime load completes;
- cycles 2–4 use listener_restart_resident_runtime;
- every listener_cancel_await_begin has a matching listener_cancel_await_finished;
- no Address already in use error;
- all seed/warm requests are HTTP 200;
- no MODEL_07_CONTEXT_CREATE_BEGIN during cycles 2–4;
- no crash;
- no unacceptable monotonic memory growth.

If this passes, RC1.23.6 can proceed to production lifecycle integration:
- Stop API listener should not automatically destroy the resident inference runtime;
- explicit Release Runtime / background lifecycle can own model teardown;
- listener restart can be independently awaited and state-driven.
