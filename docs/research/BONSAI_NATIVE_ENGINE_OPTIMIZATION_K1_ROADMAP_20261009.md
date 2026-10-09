# Native Bonsai iPad M5 27B Engine: K1–K6 research freeze
Date: 2026-10-09. Status: research-only. No runtime or certified baseline modifications.

## Fixed performance baseline
iPad Pro M5 12GB, Bonsai 2 27B PTQ1_0 GGUF, 32768 context, batch/ubatch 16/16, Q4_0 KV, 99 GPU layers, pinned Prism SHA adfffbe41b2cabcd51fff326ab045662265062bb.
Build94 measured matching 272 input tokens: 8/8 = 26.91 s, 16/16 = 9.66 s (2.78x improvement from an existing configuration, NOT a source/kernel speedup). Future A/B changes source algorithm alone, holding these settings fixed.

## Priority 1: K1 PTQ1_0 native Metal mat-vec decode kernel
Upstream Prism 2026-10-08 commit https://github.com/PrismML-Eng/llama.cpp/commit/5e9365f05e56c7d28ff596c874dcffa3da785b15
Precisely inspect and selectively port:
- ggml/src/ggml-metal/ggml-metal-impl.h — N_R0_PTQ1_0 = 5, N_R0_ID_PTQ1_0 = 4.
- ggml/src/ggml-metal/ggml-metal-device.cpp — dense and MUL_MAT_ID distinct tile selection.
- ggml/src/ggml-metal/kernels/mul_mv.metal — PTQ1 dense rows and template specializations.
Pinned Build94 baseline uses N_R0_PTQ1_0 = 4. Upstream reports M1 Max TG128 10.300→11.505 tokens/s (11.7%) and 45/45 PTQ1 MUL_MAT plus 75/75 MUL_MAT_ID checks; these numbers are not iPad M5 measurements.
Do not reuse five-row setting for MUL_MAT_ID: upstream explicitly recorded numerical failure.

## Priority 2: K2 PTQ1_0 Prefill skinny matmul kernel
Investigate pinned Prism ggml/src/ggml-metal/ggml-metal-ops.cpp lines 2791–2910 (2–8 mul_mv_ext, >8 conditional mul_mm). Build94 8→16 result suggests a route transition but does not prove the actual kernel on device. Analyze https://github.com/ggml-org/llama.cpp/issues/25250 (small batch 4–16 wasted padding and proposed 64x8 skinny tile). Profile actual shape and source type with bounded counters before trying a new Metal tile. Optimize computation at fixed 16/16, not by further batch changes.

## Priority 3: K3 model architecture kernel fusion
- 2026-09-29 GDN SIMD state rows: https://github.com/PrismML-Eng/llama.cpp/commit/445fa82098e77b6da927e0251d8636001ac12c2c
- 2026-09-28 SwiGLU + signed FWHT fusion and Qwen35 final-row narrowing: https://github.com/PrismML-Eng/llama.cpp/commit/79971a480be61252ef12fb51d08666de754f3c81
Apply one patch per independent A/B. Check Build83–89 custom Prism patch collisions and numerical equivalence.

## Conditional priorities / not next
- K4 M5 Metal Tensor execution: potentially material, but toolchain shader pipeline correctness and 32K memory are risky. https://github.com/ggml-org/llama.cpp/issues/27473 and https://github.com/PrismML-Eng/Bonsai-demo/issues/93. Separate from K1.
- K5 compressed/optimized KV: start only if measured memory or context-depth decode proves bottleneck. Already uses Q4 KV. https://github.com/TheTom/llama-cpp-turboquant
- K6 MTP/speculation: no officially released Bonsai 2 DSpark draft; Apple Metal MTP can lose throughput; defer. https://github.com/PrismML-Eng/Bonsai-demo/blob/main/SPECULATIVE.md and https://github.com/ggml-org/llama.cpp/issues/23752

## Open-source landscape and compatibility
On 2026-10-09 public GitHub stars approximately: llama.cpp 130631, Microsoft BitNet 40375, Apple MLX 28705, MLC LLM 23225, MNN 16197, PocketPal 8564, mlx-lm 7256, cactus 6113, Prism Bonsai-demo 3309, Prism llama.cpp 907. Popularity is not compatibility. Bonsai 2 PTQ1/PQ2 packed ternary plus Hadamard activation rotation requires Prism-specific operations; stock llama.cpp does not correctly load it. MLX, MLC, MNN, Cactus, BitNet are algorithm/design references, not drop-in PTQ1 engines. Verify Cactus source-available license prior to any reuse.

## K1 device/CI certification
1. Freeze Build94 as A. B differs only in the minimal native three-file Prism delta. Pin exact compiler SHA, patch SHA, IPA SHA. Do not change API Max Output Tokens in this experiment (separate usability requirement).
2. Run native PTQ1 MUL_MAT and MUL_MAT_ID numerical tests, then CI XCFramework and iOS unsigned IPA. CI SUCCESS is NOT device speed proof.
3. Fixed 32K, 16/16, Q4 KV, 99 gpu layers, same actual prompt tokens, no prefix-KV reuse, no extra device setting. A and B require separate installed binaries.
4. Primary TG128 generated-token throughput; secondary PP272/PP512, TTFT, memory peak, thermal, 32K startup, API vision/multiturn/SSE/UTF-8/JSON. Abort on EOS-shorter-than-target or explicitly mark it incomparable.
5. One-click Windows client with already known local API configuration, no interactive questions, collect /debug/build, /debug/execution, /debug/telemetry and evidence ZIP. Never publish the local key to GitHub.
6. Repeat any promising result across matched runs; use medians and report spread, not fabricated confidence. Internal candidate promotion gate: reproducible >=5% decode gain with no numeric, memory, 32K, vision or API regression; stop if repeated >=5% regression or any correctness fail.

Conclusion: Implement K1 before attempting full Prism upgrade, PQ2 model swap, new framework, speculative decoding, or additional batch-only tuning.