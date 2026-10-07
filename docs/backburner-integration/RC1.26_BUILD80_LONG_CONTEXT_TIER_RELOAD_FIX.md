# RC1.26 Build 80 — Long-Context Tier Reload Fix

## Device evidence leading to this build

Build 79 passed on iPad Pro M5 12 GB at:
- 6144 / Q8_0 / 99 GPU layers
- 8192 / Q8_0 / 99 GPU layers
- 16384 / Q4_0 / 56 GPU layers

The 32768 selection terminated the app while starting the API.

Source audit found a lifecycle mismatch: the fresh-start path applied Build 79 GPU-residency shaping, but the preserved-runtime context-switch path did not. More importantly, llama model GPU-layer placement is fixed at model load time. Rebuilding only the llama context cannot turn a model already loaded with 56 GPU layers into the intended 40-layer 32K model.

## Build 80 rule

A single long-context policy helper is now used by both fresh-start and context-switch flows.

When the target policy requests a different GPU-layer count than the currently loaded model:
1. release Vision resident state;
2. release the old llama context and model;
3. wait 600 ms so Metal/iPadOS can retire buffers and reclaim clean mmap pages;
4. mmap/load the model again using the target GPU-layer count;
5. create the target context;
6. resume the preserved API listener.

When the target GPU-layer count is unchanged, the previous lower-peak model-preserving context rebuild remains in use.

## Target policy retained from Build 79

- <= 8K: full configured GPU residency, Q8 above 4096.
- 16K: Q4_0, <=56 GPU layers.
- 32K: Q4_0, <=40 GPU layers, <=8x8.
- 64K: Q4_0, <=24 GPU layers, <=4x4.

Build 80 intentionally does not change the already device-validated 6144/8192/16K memory policy.

## New evidence

/debug/prefill exposes:
- build80_policy_source
- build80_target_context
- build80_previous_gpu_layers
- build80_target_gpu_layers
- build80_model_reload_required
- build80_model_reload_performed
- build80_reload_stage

For a 16K -> 32K switch we expect previous=56, target=40, reload_required=true, reload_performed=true, reload_stage=reload_done.
