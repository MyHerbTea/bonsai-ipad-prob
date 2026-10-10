# Build104 · integrated 32K performance and correctness

Build103 device: output cap fixed, real default completion 1999 (>256), current B8/8 and hybrid KV tail trim failure. Build104 integrates both without splitting user-visible benchmark parameters.

Persistent B24 is eligible only with same-installation prior B8, B16, B24 evidence and no sticky crash recovery. UI opt-out supported. Explicit B16 preference wins. B32 stays one-shot/high-risk consent.

KV uses seq 1 as checkpoint before final 32 prompt tokens, seq 0 for decode. Prism hybrid recurrent state does not support arbitrary generated-tail trim, but whole-sequence removal is valid. Exact token prefix match is mandatory. Clear on failure/vision/model or context switch. Dual sequence only when `context==32768` AND `kvUnified`: non-unified would otherwise halve effective per-sequence context. Feature is experimental; disable via UI if incompatible.

CI gates Swift policy, source invariants, Prism/Xcode IPA build, Python runner dry run. Real-device gates: actual Batch24, context32K, authenticated Build104 identity, output >256, deliberate KV hit with positive reused tokens, 1–3 pictures and text-after-vision, long inputs, multi-turn and SSE. Runner generates its own 256x256 image if Windows has no image. NO source-only promotion to Stable.

Usage: install Build104, start local OpenAI API. Extract artifact `Bonsai-Build104-OneClick-FullStage.zip`. Double-click `RUN_BUILD104_FULL_STAGE.cmd`, paste API Key through graphical dialog (no invisible terminal getpass). Upload `RESULTS/Build104-FULL-*.zip` only. No API key, image bytes or response text in report.

Caveat: Real context *allocation* of 32768 is distinct from validated 32K-full prompt throughput. Longest default text case is approximately 3600 actual tokens; substantial 16–32K capacity, sustained decode, and peak memory remain a separate release gate and cannot be claimed merely because Build104 compiles.
