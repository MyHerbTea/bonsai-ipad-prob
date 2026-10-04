# RC1.23.6 Build 53 — True-Device Evidence

Status: **PASS**

Device:
- iPad Pro M5-class test device
- iPadOS 27.0.1
- physical memory reported by app: 11524 MiB

Build:
- 53
- API context: 512
- batch: 8
- ubatch: 8
- runtime profile: Accelerated
- Prefix KV reuse: enabled
- strategy: cycle 1 full runtime load, cycles 2–4 listener-only restart
- listener rebind: await old listener cancelled, then bind the same port

## Lifecycle result

All four cycles completed.

Cycle 1:
- full runtime load
- seed HTTP 200
- warm HTTP 200
- 115 completion tokens
- finish_reason=stop

Cycles 2–4:
- restart_mode=listener_restart_resident_runtime
- old listener cancellation completed before new listener installation
- engine stage remained TWOPHASE_VISION_99_PASS across each restart
- listener returned ready
- seed HTTP 200
- warm HTTP 200
- 115 completion tokens
- finish_reason=stop

Final cleanup completed:
- final API stop
- final engine unload
- recorder status completed
- summary PASS

No recurrence of:
- MODEL_07_CONTEXT_CREATE_BEGIN crash
- Address already in use
- stale listener ready state
- API connection failure

## Resource result

Across the resident-runtime cycles:
- Metal allocated remained 6109 MiB
- available memory remained approximately 4452–4455 MiB
- physical footprint remained approximately 664–667 MiB
- thermal state remained nominal
- low power mode remained false

There is no evidence of monotonic memory growth.

## Performance observation

A separate throughput degradation remains visible during repeated requests.

Representative warm-path values:
- early warm: about 12.5 tok/s
- later warm: about 8.3–8.4 tok/s

Prefill and decode time increased while:
- Metal allocation stayed constant
- available memory stayed stable
- thermal state remained nominal
- Prefix KV reuse remained HIT + retained=true

This is not treated as an RC1.23.6 lifecycle failure. It is consistent with the
previous RC1.23.5 repeated-request performance investigation, which closed with
no safe production optimization. Build 54 must not modify sampler, model,
context, batching, C2-B, or inference kernels while integrating lifecycle UX.

## Architectural conclusion

The true-device evidence now supports this production rule:

**LAN listener lifecycle and resident 27B inference-runtime lifecycle must be
separate.**

Normal user Stop/Resume should operate on the listener only.

Full runtime release remains appropriate for explicit lifecycle boundaries such
as app backgrounding or changing critical model assets.
