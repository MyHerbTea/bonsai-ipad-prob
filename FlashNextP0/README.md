# FlashNextP0

Standalone iPad probe for **FlashNext-iPad / Bonsai-Niwaki**.

This target is intentionally isolated from the Bonsai production application. It does not link the Prism 27B runtime, does not touch the OpenAI API, and does not modify Bonsai UI/runtime files.

## P0-A question

Can an M5 iPad execute a **real Niwaki v2.4 3-bit affine routed-expert projection** through MLX/Metal?

Reference checkpoint:

`neopolita/Qwen3.8-Flash-Next-102B-A5B-Niwaki-v2.4-3bit-mlx`

The model card states expert precision 3-bit group 64, PLE 2-bit group 128, backbone 4-bit, full checkpoint ~37.5 GB, and MLX >= 0.32.

The probe pins MLX Swift **0.32.3**, while Bonsai can continue to pin its validated 0.31.3 dependency.

## Asset

For P0-A, do **not** download the full 37.5 GB checkpoint.

Use `model-00008-of-00008.safetensors` plus the small config/index files for PC-side inspection.

The probe dynamically finds a `.switch_mlp.*.weight` tensor with matching `.scales` and `.biases`, slices one real expert, and executes `quantizedMM(... bits: 3, groupSize: 64, mode: .affine)`.

## PASS

P0-A passes when the physical iPad reports:

- `result=PASS`
- `nan_count=0`
- `inf_count=0`
- non-empty output
- no Jetsam / Metal OOM
- bounded MLX and process footprint

P0-A is a kernel/layout compatibility probe only. It does not prove full model correctness.

## Next gate

Only after P0-A passes:

1. P0-B — real 2-bit PLE/n-gram subset
2. P0-C — SSD random/streaming behaviour
3. 4-layer qwen4_exp parity
4. full 48-layer text-only runtime

The full 37.5 GB checkpoint remains blocked until P0-A/B/C pass.
