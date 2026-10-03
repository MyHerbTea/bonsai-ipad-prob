# RC1.23.0 — Live Vision Injection

## Frozen baselines

- RC1.20.7: resident 27B text/OpenAI API — real-device PASS.
- RC1.21.2: BVCACHE1 projected embeddings can be prefilling into the resident llama context and produce correct image answers — real-device PASS.
- RC1.22.5: MLX Hard Graph-Cut Vision beside resident 27B — real-device PASS.
  - source 512x732
  - resize 192x288
  - raw patch rows 216
  - projected output 54x5120
  - image encode 0.317 s
  - MLX active/cache/peak 95/0/144 MiB

## Live bridge

RC1.23.0 keeps the RC1.22.5 hard graph-cut execution unchanged and adds an App-local injection gate.

The sidecar now exports the final merger output as Float32 projected embeddings plus merged grid width/height.

The native bridge persists those embeddings as the existing BVCACHE1 format with Qwen M-RoPE metadata:
- token_count = grid_x * grid_y
- n_pos = max(grid_x, grid_y)
- relative t = 0
- relative row/column positions match mtmd's M-RoPE decoder layout
- z = 0
- non_causal = false

The existing BonsaiPrefillCachedVision / generateCachedVision implementation then injects the cache into the already-resident Swift llama model/context.

## Safety invariant

The Live Injection path:
- requires the OpenAI API/text runtime to already be resident;
- never initializes Q8 mmproj;
- never unloads or recreates the 27B model/context;
- reuses the proven BVCACHE1 prefill and native non-thinking generation path.

## First device acceptance

1. Start OpenAI API and wait for resident 27B text runtime.
2. Select vision_tower.safetensors and the existing test image.
3. Press "运行 Live Vision Injection".
4. PASS requires:
   - MLX_INJECT_03_PACKET_READY
   - MLX_INJECT_12_CACHE_READY
   - TWOPHASE_B99_PREFILL_READY
   - semantically correct image answer
   - App remains alive
   - text API still returns HTTP 200 afterwards.

Only after this App-local gate passes should RC1.23.1 replace the LAN API image path.
