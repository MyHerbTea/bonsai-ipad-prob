# RC1.22.2 — Lazy Vision Materialization

## Real-device evidence from RC1.22.1

With the Prism PTQ1_0 27B model and llama context resident, the staged MLX admission probe reached:

MLX_ADMIT_21_MODEL_EVAL_BEGIN
active=0 MiB
cache=0 MiB
peak=0 MiB
cacheLimit=20 MiB

and the process terminated before MODEL_EVAL_DONE.

Therefore:
- MLX tensor smoke beside resident 27B works;
- vision safetensors open/load succeeds;
- local vision-weight filtering succeeds;
- VisionModel construction succeeds;
- sanitize succeeds;
- parameter update/binding succeeds;
- failure is triggered by eager evaluation/materialization of the entire FP16 VisionModel.

## Changes

1. Remove eval(created) from vision-weight loading.
2. Load safetensors explicitly on the MLX CPU stream.
3. Keep parameters lazy/CPU-backed until the real forward graph needs them.
4. Preserve the 20 MiB MLX reusable cache and explicit clearCache boundaries.
5. Reduce the first coexistence image admission tier to <=65,536 pixels (~256x256 class), with a 32,768-pixel minimum.
6. Persist new stages:
   - MLX_LAZY_21_EAGER_EVAL_SKIPPED
   - MLX_LAZY_24_WEIGHTS_BOUND
   - MLX_LAZY_30_PRE_FORWARD_READY
   - MLX_LAZY_40_FORWARD_BEGIN
   - MLX_LAZY_41_FORWARD_DONE
   - MLX_LAZY_99_PASS

## Acceptance

Start the frozen text API first so PTQ1_0 27B + llama context are resident, then run one MLX Lazy Vision Probe.

If the process terminates:
- report MLX Vision Stage
- report MLX Vision Metrics

Interpretation:
- dies before MLX_LAZY_40_FORWARD_BEGIN: preprocessing/weight-lifetime issue;
- dies at MLX_LAZY_40_FORWARD_BEGIN: real forward working-set is still too large and the next step is vision-weight quantization or nonresident streaming;
- reaches MLX_LAZY_99_PASS: eager full-model materialization was the root cause and RC1.22.3 can proceed to embedding parity/live injection.
