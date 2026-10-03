# RC1.22.4 — Streaming Vision Weights

## Real-device evidence

RC1.22.3 reached MLX_LAYER_20_BEGIN with:

- active = 563 MiB
- cache = 4 MiB
- peak = 583 MiB
- cacheLimit = 20 MiB

Blocks 1 through 19 completed successfully while the frozen Prism 27B + llama context remained resident.

All 27 vision blocks are structurally identical and deepstackVisualIndexes is empty. Therefore block 20 is not a special architecture boundary.

The observed pattern indicates that per-layer eval barriers worked, but the already-materialized block parameters remained strongly referenced by VisionModel.blocks[]. Memory.clearCache() cannot free active parameter storage.

## RC1.22.4 architecture

- Load all safetensor arrays on the MLX CPU stream.
- Sanitize once.
- Bind only patch_embed, pos_embed, merger and other non-block parameters to the long-lived VisionModel shell.
- Keep all blocks.* arrays in a CPU/lazy dictionary.
- During forward, for each layer:
  1. create one short-lived VisionBlock;
  2. strip blocks.N. prefix from that layer's parameter dictionary;
  3. update the local block with exactly those parameters;
  4. run that single layer;
  5. eval the output;
  6. let the block/module fall out of scope;
  7. clear the reusable MLX cache;
  8. proceed to the next layer.

No block weight is permanently bound to VisionModel.blocks[].

## Expected memory signature

Instead of active memory growing roughly with layer index, active memory should plateau around the working set of:
- resident hidden states;
- positional/rotary tensors;
- one FP16 VisionBlock;
- transient attention/MLP activations.

## Stages

- MLX_STREAM_24_WEIGHTS_READY
- MLX_STREAM_30_PRE_FORWARD_READY
- MLX_STREAM_00_PATCH_BEGIN / DONE
- MLX_STREAM_01_BEGIN / DONE
- ...
- MLX_STREAM_27_BEGIN / DONE
- MLX_STREAM_28_MERGER_BEGIN / DONE
- MLX_STREAM_99_FORWARD_DONE
- MLX_STREAMING_99_PASS

## Acceptance

Keep the frozen 27B text runtime resident and run one Streaming-Weights Vision Probe.

PASS:
- reaches MLX_STREAMING_99_PASS;
- Vision output shape is [N, 5120];
- App stays alive;
- active memory does not monotonically climb with layer number;
- text API remains responsive afterwards.

If the process still terminates, the last stage + allocator metrics will tell whether a single VisionBlock itself exceeds the remaining coexistence headroom. At that point the justified next step is block-weight quantization, not more lifetime tuning.
