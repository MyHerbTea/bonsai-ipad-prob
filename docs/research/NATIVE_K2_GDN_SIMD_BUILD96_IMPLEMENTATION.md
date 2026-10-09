# Build96 Native K2 — GDN 4-row SIMD pilot

**Status:** implementation branch / not stable / no iPad test until compiled and A/B compared.
**Product baseline:** Build94 `aeb0f0c4d1918bc5618aba5d883404cc04436067`.
**Prism pin:** `adfffbe41b2cabcd51fff326ab045662265062bb`.
**Upstream selected delta:** [Prism 445fa82098e77b6da927e0251d8636001ac12c2c](https://github.com/PrismML-Eng/llama.cpp/commit/445fa82098e77b6da927e0251d8636001ac12c2c), Sep 29 2026.
**K1 exclusion:** this branch was created from Build94 rather than Build95. PTQ1 dense mat-vec retains `N_R0_PTQ1_0 = 4`; do NOT apply Build95 5-row K1. Do not merge K1 and K2.

## Scope and causal hypothesis

Ternary-Bonsai 2 27B GGUF reports `qwen35` hybrid architecture with 48 Gated DeltaNet blocks and 16 full-attention blocks. Per-token GDN state computation can be a real non-PTQ hotspot. Test experimentally rather than assume its wall-time dominance.

Exactly two native files change in the **external, frozen Prism checkout**, after the Build83-89 essential 32K scheduler/KV patches and before XCFramework build:

- `ggml/src/ggml-metal/ggml-metal-ops.cpp`: GDN dispatch grid X changes from `ne[0]/nsg` to `ne[0]/(4*nsg)`.
- `ggml/src/ggml-metal/kernels/gated_delta_net.metal`: four state rows per simdgroup, 8 lanes per row, segment-dependent state and k/q/v loads, subgroup XOR reductions. Both output and state writes updated.

Vendored `tools/patches/k2_prism_445fa820_gdn_4rows.patch` is the exact two-file unified diff as published in the pinned Prism commit; `tools/rc126_build96_patch_prism_gdn_simd.py` checks source anchors, two-file whitelist, unchanged Prism HEAD and `git apply --check` before writing. Keep any other Prism changes out.

## Gates

1. Python static contract tests, Swift policy, inherited product regressions and correct Build96 packaging identity.
2. Source-level actual patch application on pinned Prism `adfffbe`; `git diff --check`. Prefer dedicated native `test-backend-ops` `GATED_DELTA_NET` numeric tests on the macOS runner when supported. Report test output; no fake certification.
3. macOS GitHub Actions successfully compiles patched `ios-arm64` Prism XCFramework, complete Xcode iPad app and uploads unsigned IPA; record SHA, workflow ID and signing disclaimer. CI compiled does not imply M5 runtime safe.
4. On real M5 with same PTQ1 GGUF, 32768 ctx, Q4 KV, GPU99, Flash Attention and **verified actual 16/16**: compare Build94 vs Build96 with controlled **TG128** (Decode-only native reported t/s), PP272 / PP512, 1–3 image tests, multi-turn/vision-follow-up, UTF-8/SSE.
5. Verify output hashes/greedy results and native op numerical correctness; record early EOS, exact token counts, prefix reuse, thermal state and memory. For long contexts test admission/start first, then progressively longer requests; never request full 32K input plus extra decode in 32K.
6. Promotion only after material repeatable gain and zero correctness/crash regressions. The reported Build94 TG128 median is **12.663 tok/s**, measured in three samples; K1 Build95 median **12.818 tok/s** (+1.22%, not promoted). Keep the corresponding ZIP evidence accessible; do not call K1 a proven substantial gain.

## K3 remains separate

Prism `79971a480be61252ef12fb51d08666de754f3c81` (SwiGLU + signed FWHT) touches Metal device, ops, misc kernels, Qwen3.5 graph and tests. It reported M5 Pro/PQ2_0 gains around 1% for TG, **not evidence of PTQ1 M5 iPad benefit**. Do not mix it into Build96.

## Known limitation

Without a Mac or Xcode Instruments attached to the user iPad, GitHub macOS CI can compile and unit-test Metal, but cannot obtain an M5 iPad Metal System Trace. End-to-end measurements should be interpreted as actual tokens/s, not per-kernel utilization. Numerical validation against genuine device behavior is still required.
