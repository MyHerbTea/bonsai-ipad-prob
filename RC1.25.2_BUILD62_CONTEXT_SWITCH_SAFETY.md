# RC1.25.2 Build 62 — Context Switch Safety

## Trigger

Build 61 device testing established that 768, 1024, and 2048 contexts can run
real inference, and the full 2048 OpenAI-compatible API matrix passed.

During repeated device ladder work, however, changing API Context/Profile after
stopping the listener could terminate the app. Relaunching the app and starting
with the selected context worked normally.

## Root cause in the Build 61 lifecycle

The paused API intentionally kept the 27B runtime resident. When the user then
changed Context/Profile, Build 61 treated the mismatch as a full runtime reload:

1. clear the server handler;
2. call `startAPIServer()`;
3. call `engine.unloadAll()`;
4. call `loadModel()`, which itself calls `unloadAll()`;
5. remap the 27B model;
6. create the new llama context.

This was unnecessarily destructive for a context-only change and crossed a
high-memory in-process teardown/remap/recreate boundary. Existing Bonsai engine
history already contains device evidence that some large-runtime recreate
boundaries can terminate the process even when a clean-process start succeeds.

The Build 61 API correctness result therefore remains valid, but the context
switch UX was not safe enough to freeze.

## Build 62 fix

When a stopped API still has a preserved runtime and only Context/Profile
changed, Build 62 now:

1. keeps the mmap-backed 27B model and vocab resident;
2. releases MLX Vision resident shell/cache state;
3. clears API vision-prefix reuse state;
4. releases only the old llama context;
5. creates a new llama context with the selected Context/Profile;
6. updates active runtime metadata only after successful context creation;
7. restores the API listener using the existing handler;
8. avoids remapping the 27B model.

If target context creation fails, the engine performs a best-effort rollback to
the previous context.

## Crash-stage evidence

Build 62 persists:

- `BonsaiRC1252ContextSwitchState`
- `BonsaiRC1252ContextSwitchFrom`
- `BonsaiRC1252ContextSwitchTo`

Engine stages include:

- `CTX_SWITCH_00_BEGIN_<from>_TO_<to>`
- `CTX_SWITCH_01_CONTEXT_RELEASE_BEGIN`
- `CTX_SWITCH_02_CONTEXT_RELEASE_DONE`
- `CTX_SWITCH_03_CONTEXT_CREATE_BEGIN_CTX_<to>`
- `CTX_SWITCH_04_READY_CTX_<to>`
- rollback/failure stages

These values are surfaced in the diagnostic snapshot after relaunch, so a
remaining device termination can be located instead of inferred.

## Device acceptance gate

Do not rerun the full 2048 API matrix first. Build 61 already passed that
matrix. Build 62 must first prove the lifecycle fix with repeated switches:

- 512 -> 2048
- 2048 -> 512
- 512 -> 1024
- 1024 -> 2048

For each switch:

1. stop API using the product button;
2. change Context;
3. apply/resume;
4. require no process termination;
5. require `/v1/models.context_length` to match;
6. run one short inference.

Only after this lifecycle gate passes should Build 62 receive a final 2048
smoke/certification pass and be considered for freeze.
