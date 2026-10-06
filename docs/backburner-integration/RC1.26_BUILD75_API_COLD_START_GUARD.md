# RC1.26 Build 75 — API Cold-Start Guard

## Motivation

Build 74 exposed a reproducible usability defect on the iPad Pro M5:
- immediately after installing/cover-installing the build,
- first app launch,
- select/configure the 27B model,
- start the OpenAI API,
- the app can terminate,
- opening the app again and repeating the same model/API setup succeeds.

Phase 2F itself is closed. 32×32 is the selected batch shape; 64×64 is not promoted.

## Build 75 scope

Build 75 does not continue the batch ladder. It isolates startup lifecycle stability.

The first API bootstrap is staged as:
1. Persist startup BEGIN.
2. Release any resident MLX Vision state.
3. Prewarm the llama/Prism backend without the 27B model mapped.
4. Persist pre/post-backend resource diagnostics.
5. Give the process one short scheduling boundary for transient Metal/backend resources to settle.
6. Map the 27B model and create its context.
7. Bind the API listener.
8. Wait for the API health path to become ready.
9. Persist READY.

If the process is killed between steps, the stage remains persisted. On the next startup attempt, the prior non-terminal stage is copied into `BonsaiRC126APIPreviousIncompleteStage` before the new attempt begins.

## Safety boundaries

- Frozen Build 64 remains immutable.
- Metal Tensor remains disabled.
- No 64×64 or 128×128 promotion.
- Build 75 expects the selected Phase 2F baseline arm: 32×32.
- Vision request behavior is unchanged.
- OpenAI request/response semantics are unchanged.
- The startup guard changes only initialization sequencing, readiness gating, and diagnostics.

## Device gate

After cover-installing Build 75:
1. Launch the app for the first time.
2. Select the same 27B model.
3. Start the API once.
4. The app must remain alive and the API must become ready.
5. Run `tools/rc126_build75_api_cold_start_probe.ps1`.

A clean first-start pass should show:
- `startup_stage=READY`
- `startup_previous_incomplete=none`
- `active_batch=32`
- `active_ubatch=32`

If the app still terminates, reopen it, start the API again, and run the probe. `startup_previous_incomplete` will identify the last persisted stage from the terminated attempt.
