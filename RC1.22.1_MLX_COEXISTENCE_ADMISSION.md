# RC1.22.1 — MLX Coexistence Admission

RC1.22.0 compiled and installed successfully, and the UI/MLX integration loaded without crashing. The process terminated only after the user ran the full MLX Vision Sidecar Probe while the Prism 27B + llama context were resident.

RC1.22.1 turns that one opaque operation into a staged admission sequence.

## Persistent stages

- MLX_ADMIT_00_BEGIN
- MLX_ADMIT_01_TENSOR_SMOKE_BEGIN
- MLX_ADMIT_02_TENSOR_SMOKE_PASS
- MLX_ADMIT_03_CACHE_CLEARED
- MLX_ADMIT_10_LOAD_ARRAYS_BEGIN
- MLX_ADMIT_11_LOAD_ARRAYS_DONE
- MLX_ADMIT_13_FILTER_WEIGHTS_DONE
- MLX_ADMIT_14_MODEL_INIT_BEGIN
- MLX_ADMIT_15_MODEL_INIT_DONE
- MLX_ADMIT_16_SANITIZE_BEGIN
- MLX_ADMIT_17_SANITIZE_DONE
- MLX_ADMIT_18_UPDATE_BEGIN
- MLX_ADMIT_19_UPDATE_DONE
- MLX_ADMIT_21_MODEL_EVAL_BEGIN
- MLX_ADMIT_22_MODEL_EVAL_DONE
- MLX_ADMIT_23_POST_LOAD_CACHE_CLEARED
- MLX_ADMIT_24_WEIGHTS_READY
- MLX_ADMIT_30_PREPROCESS_BEGIN
- MLX_ADMIT_40_ENCODE_BEGIN
- MLX_ADMIT_41_ENCODE_DONE
- MLX_ADMIT_99_PASS

Every mark also persists MLX active/cache/peak allocator MiB so a process-level exit still leaves actionable evidence after relaunch.

## Memory hardening

The original probe allowed a 384 MiB reusable MLX cache. RC1.22.1 follows MLX's iOS guidance and uses a 20 MiB cache during coexistence bring-up, explicitly clearing recyclable buffers:
- before tensor smoke
- after tensor smoke
- before vision weight loading
- before model materialization
- before image encode
- after success

This does not unload or alter the frozen Prism 27B runtime.

## Acceptance

Start the OpenAI API first so the 27B + text context are resident, then run one admission probe.

If the app terminates, relaunch and report only:
- MLX Vision Stage
- MLX Vision Metrics

Those two fields identify the exact unsafe boundary without another blind test.
