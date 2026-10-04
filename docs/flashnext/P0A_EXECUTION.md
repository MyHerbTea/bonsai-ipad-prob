# FlashNext-iPad P0-A Execution Gate

Status: **ACTIVE EXPERIMENT**

Branch: `experiment/flashnext-ipad-p0`

## Isolation decision

Bonsai is still converging toward a stable release. P0-A is therefore a separate iPad application and separate XcodeGen spec.

P0-A must not modify:

- `BonsaiLab/`
- root `project.yml`
- the existing Bonsai build workflow
- OpenAI API
- Prism 27B runtime
- current Vision runtime

When Bonsai reaches its stable/frozen release, validated FlashNext components can be migrated forward deliberately.

## Why MLX Swift 0.32.3

Niwaki v2.4 explicitly requires MLX >= 0.32. The current Bonsai baseline pins MLX Swift 0.31.3.

Changing Bonsai's MLX dependency during stabilization would create an unnecessary regression surface, so FlashNextP0 pins MLX Swift 0.32.3 independently.

## P0-A experiment

Input: `model-00008-of-00008.safetensors`

Procedure:

1. Select the shard in the standalone FlashNext P0 app.
2. Load the safetensors map on the CPU stream.
3. Find a real routed `switch_mlp` projection with weight/scales/biases.
4. Slice expert 0 only.
5. Infer logical input width from the packed 3-bit UInt32 representation.
6. Execute MLX `quantizedMM` with bits=3, groupSize=64, mode=affine.
7. Evaluate and record MLX/system memory telemetry.

## PASS gate

Required:

```text
result=PASS
nan_count=0
inf_count=0
output_count>0
```

Also required operationally: App stays alive, no Jetsam, no Metal OOM, and footprint stays within an obviously safe range.

## What P0-A does NOT prove

It does not prove full qwen4_exp graph correctness, router correctness, full MoE inference, 2-bit PLE support, SSD streaming performance, full 48-layer feasibility, or text quality.

## After PASS

Proceed to P0-B by extracting a minimal real 2-bit PLE/n-gram tensor subset instead of downloading a full multi-GB shard.
