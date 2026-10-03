# RC1.22.0 — MLX Vision Sidecar Bootstrap

## Frozen parents

- `frozen-v1-rc1-20-7-text-api`: real-device passed 27B OpenAI text runtime.
- `frozen-v1-rc1-21-2-two-phase-cache`: real-device passed cached image embeddings → stable 27B context.

RC1.22.0 does not replace either frozen baseline.

## Objective

Test one question only:

> Can a ~0.92GB Qwen3.5/Qwen3.8 Vision Tower run through MLX/Metal while the
> RC1.20.7 Prism 27B model + llama context remain resident in the same iPad M5 process?

If yes, the mtmd lifecycle conflict can be removed without reloading the 27B model.

## Implementation

- iOS deployment target is raised to 17.0 on this experimental branch because mlx-swift-lm requires iOS 17+.
- The Vision Tower implementation is vendored from mlx-swift-lm 3.31.3, but the App links only mlx-swift 0.31.3 (MLX + MLXNN). This avoids pulling the full MLXVLM package and keeps Xcode 16.4 compatibility.
- Only the upstream Qwen3VL Vision Tower core and the minimal image-preprocessing math are adapted into Bonsai.
- No MLX language model is instantiated.
- Prism llama.cpp remains the sole 27B language runtime.
- Vision configuration is pinned to Bonsai 2 / Qwen3.8:
  - depth 27
  - hidden 1152
  - MLP 4304
  - output width 5120
  - 16 heads
  - patch 16
  - temporal patch 2
  - spatial merge 2
  - 2304 position embeddings
- First probe is bounded to about 128 final visual tokens (~131072 pixels), matching the existing 512-tier lifecycle experiment.
- MLX temporary-buffer cache is capped at 384 MiB.
- Probe records weight-load time, image-encode time, output shape, and MLX active/cache/peak memory.

## Vision-only asset

`tools/extract_bonsai_vision_tower.py` uses HTTP Range requests against Prism's
single 8.6GB MLX safetensors file and downloads only tensors belonging to the
vision tower. It refuses to continue if the server does not honor byte ranges.

Example:

```powershell
python .\extract_bonsai_vision_tower.py
```

Expected output is roughly 0.92GB:
`Bonsai-2-27B-vision_tower-fp16.safetensors`

## Device acceptance

1. Install RC1.22.0.
2. Select the normal PTQ1_0 27B GGUF and a test image.
3. Start OpenAI API and wait until the 27B text runtime is ready.
4. In Advanced → MLX Vision Sidecar Probe, select the extracted safetensors.
5. Run the probe while the API remains running.

PASS:
- App does not terminate.
- MLX Vision Stage reaches `MLX_VISION_99_PASS`.
- Output dimension is 5120.
- Output token count is non-zero and close to the intended 128-token tier.
- Text API remains alive after the probe.

RC1.22.0 intentionally does not yet write BVCACHE1 or route LAN image requests through MLX. That is RC1.22.1 after coexistence is proven on M5.
