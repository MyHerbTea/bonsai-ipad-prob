# RC1.22.5 — Hard Graph Cut

## Real-device evidence

RC1.22.4 produced the exact same failure signature as RC1.22.3:

MLX_STREAM_20_BEGIN
active=563 MiB
cache=4 MiB
peak=583 MiB
cacheLimit=20 MiB

That disproves the hypothesis that VisionModel.blocks[] ownership alone caused the active-memory accumulation.

Two additional retention paths remain plausible:
1. the long-lived streamingVisionWeights dictionary keeps all MLXArray handles alive after materialization;
2. evaluated hiddenStates may still retain the previous lazy graph and its weight dependencies.

## RC1.22.5 changes

### Per-layer safetensor lifetime
No blocks.* dictionary is stored on the sidecar actor.

For every transformer block:
- reopen the safetensor file on the CPU stream;
- normalize only that block's keys;
- create one local VisionBlock;
- bind only that block's parameters;
- execute and evaluate;
- let all block arrays and the local module fall out of scope.

### Hard activation graph cut
After every block output is evaluated:
- call output.asData(access: .copy);
- this creates an independent contiguous CPU copy whose lifetime does not depend on the source MLXArray;
- reconstruct MLXArray(data: snapshot);
- return only that fresh array to the next block.

PatchEmbed, positional-addition and Merger boundaries receive the same CPU-copy graph cut.

## Expected diagnostic signature

If MLX graph/array lifetime is the root cause:
- active memory should no longer increase monotonically through layers;
- MLX_CUT_20_BEGIN should be far below the previous 563 MiB;
- the run should reach MLX_HARDCUT_99_PASS.

The cost is additional CPU<->MLX copies and repeated safetensor metadata loads. RC1.22.5 is a correctness/lifetime experiment, not the final performance design.

If active still reaches ~563 MiB at layer 20, the retained memory is below Swift object lifetime (e.g. MLX allocator/file-backed GPU residency). The next justified direction is quantized Vision weights or a different execution backend.
