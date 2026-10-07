# RC1.26 Build 79 — Storage–Memory Long Context

## Objective
Maximize usable context on iPad Pro M5 12 GB. 4096 is a regression baseline, not the target.

The Ternary Bonsai 2 27B model natively supports 262,144 tokens. Build 79 raises the app runtime ceiling to 65,536 for the first long-context device campaign.

## Context policy
- <=4096: F16 KV, unchanged baseline.
- 6144 / 8192: Q8_0 K/V.
- >=16384: Q4_0 K/V.
- Long-context modes force Flash Attention because Prism requires it for quantized V.

## Storage-memory co-design
GGUF remains LLAMA_LOAD_MODE_MMAP. For large contexts, GPU residency is reduced so more model weights remain CPU/file-backed and clean pages can be reclaimed and faulted again from storage.

- <=8192: existing full GPU-layer target.
- 16K: <=56 GPU layers.
- 32K: <=40 GPU layers.
- 64K: <=24 GPU layers.

Compute shape is also reduced:
- 6144/8192/16K: <=16x16.
- 32K: <=8x8.
- 64K: <=4x4.

## iPadOS capabilities
The project requests:
- com.apple.developer.kernel.increased-memory-limit
- com.apple.developer.kernel.extended-virtual-addressing

Third-party re-signing may remove or fail to grant these. Build 79 therefore queries the effective running-task entitlement using SecTaskCopyValueForEntitlement; it never assumes the source entitlement survived signing.

## Memory evidence
Snapshots are persisted before/after model mmap and before/after context creation. Each snapshot includes process available memory, resident/virtual/physical footprint, effective memory entitlements, Metal current allocation and recommended working set.

The /debug/telemetry response reports Build 79 context, KV type, GPU layers and post-context memory state.

## Device campaign
Test in this order:
1. 6144
2. 8192
3. 16384
4. 32768
5. 65536

Failure at a tier means the memory policy needs another iteration. It does not redefine the previous tier as the product ceiling.
