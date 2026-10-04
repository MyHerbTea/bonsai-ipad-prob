# RC1.23.6 Build 54 — Production Stop / Resume

Status: **PRODUCT LIFECYCLE INTEGRATION CANDIDATE**

Parent evidence:
- Build 50 isolated unsafe same-process full context recreation
- Build 52 isolated same-port listener cancellation race
- Build 53 passed four true-device cycles with awaited listener cancellation
  while preserving the resident 27B runtime

## Goal

Promote the Build 53 validated lifecycle from certification-only behavior into
the actual product controls.

## Product behavior

### Stop API

The normal `停止 API` action:

1. stops only the Network listener;
2. waits for listener cancellation;
3. preserves the OpenAI handler closure;
4. preserves the resident 27B model/context;
5. does **not** call `engine.unloadAll()`.

The UI reports that the API is stopped while the Runtime remains resident.

### Resume API

When a preserved runtime exists, the normal start control changes to
`恢复 OpenAI API`.

Resume:

1. reuses the preserved OpenAI handler;
2. binds a new listener on port 8080;
3. uses the Build 53 awaited-cancel/generation-guard implementation;
4. does not reload the 27B model/context.

If no preserved runtime exists, the normal cold `startAPIServer()` path is
used.

## Full-release boundaries

A preserved handler/runtime must not survive a change to assets captured by the
handler.

Build 54 performs a full API stop + engine unload when changing:
- main model;
- mmproj;
- MLX Vision Tower.

Entering app background continues to perform:
- full API stop;
- engine unload.

The certification runner's final cleanup also remains a full release.

## Build 54 certification

The one-click runner continues to emit one `BONSAI-RUN-*.json`.

Cycle 1:
- clean full runtime load;
- seed;
- warm.

Cycles 2–4:
- call the same product listener-stop helper used by the UI;
- verify API stopped and runtime remains resumable;
- call the same product resume helper used by the UI;
- wait for ready;
- seed;
- warm.

Recorded product events:
- product_stop_requested
- product_stop_completed
- product_resume_requested
- product_resume_ready

## Frozen inference behavior

Unchanged:
- Accelerated
- context 512
- batch 8
- ubatch 8
- n_seq_max 1
- C2-B
- Prefix KV reuse
- MLX Live Vision Injection
- max completion tokens 128 in certification
- stream=false in certification
- reasoning_effort=none in certification

The Build 53 repeated-request throughput decline is explicitly outside this
change.

## Acceptance

PASS requires:
- all four cycles complete;
- cycles 2–4 use product stop/resume helpers;
- each product stop reports api_running=false;
- each product stop reports runtime_resumable=true;
- each product resume reaches api_running=true;
- engine stage remains TWOPHASE_VISION_99_PASS;
- all seed/warm requests return HTTP 200;
- no MODEL_07_CONTEXT_CREATE_BEGIN recurrence;
- no Address already in use;
- no crash;
- no monotonic memory growth.

A later RC1.23.6 step should separately address safe draining of in-flight
request handlers before full engine teardown. That concern is not silently
claimed solved by Build 54.
