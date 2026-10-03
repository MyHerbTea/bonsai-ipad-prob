# RC1.22.3 — Layerwise Vision Execution

## Real-device evidence

RC1.22.2 successfully:
- skipped whole-model eager eval;
- kept safetensor weights CPU/lazy-backed;
- completed image preprocessing at the reduced admission tier;
- reached MLX_LAZY_40_FORWARD_BEGIN.

The process terminated before the whole-graph forward returned, with allocator metrics still 0/0/0 MiB at the last persisted marker.

The remaining issue is therefore the first materialization of the complete 27-layer lazy vision graph.

## Change

VisionModel forward is now execution-barriered:

1. PatchEmbed -> eval -> clearCache.
2. Positional embeddings -> eval.
3. Rotary/cumulative sequence tensors -> eval.
4. For each of 27 transformer blocks:
   - mark MLX_LAYER_NN_BEGIN;
   - execute only that block;
   - eval(hiddenStates);
   - materialize any deepstack feature;
   - clear MLX reusable cache;
   - mark MLX_LAYER_NN_DONE.
5. Merger -> eval -> clearCache.
6. Return an already-materialized final embedding.

This constrains graph lifetime and exposes the exact transformer block if the device still reaches a working-set wall.

## Diagnostic stages

- MLX_LAYER_00_PATCH_BEGIN / DONE
- MLX_LAYER_00_POSITION_DONE
- MLX_LAYER_00_ROTARY_DONE
- MLX_LAYER_01_BEGIN / DONE
- ...
- MLX_LAYER_27_BEGIN / DONE
- MLX_LAYER_28_MERGER_BEGIN / DONE
- MLX_LAYER_99_FORWARD_DONE
- MLX_LAYERWISE_99_PASS

Developer Diagnostics now labels the allocator line explicitly as "MLX Vision Metrics".

## Acceptance

Keep the frozen 27B text runtime resident and run one Layerwise Vision Probe.

PASS:
- MLX_LAYERWISE_99_PASS
- output shape [N, 5120]
- App stays alive
- text API remains responsive afterwards.

If the process terminates, the last layer marker directly identifies the first block whose materialization exceeds the coexistence envelope. The next optimization can then target block weight quantization/streaming instead of guessing.
