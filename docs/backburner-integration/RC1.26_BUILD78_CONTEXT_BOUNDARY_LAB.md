# RC1.26 Build 78 — M5 Context Boundary Lab

## Device evidence from Build 77

On the iPad Pro M5 12 GB:

- 4096 context: API startup succeeds.
- 6144 context: tapping Start API terminates the app.
- 8192 context: tapping Start API terminates the app.

The termination happens during API/runtime startup, before an ordinary Swift error can be surfaced. The most likely boundary is native/Metal context-allocation peak pressure or iPadOS jetsam. Build 78 therefore treats 6144/8192 as known-unsafe on the current runtime rather than repeatedly crashing the device.

## Build 78 ladder

Selectable:

- 512 / 768 / 1024 — legacy
- 2048 — old certification baseline
- 3072 — transition
- 4096 — **device-verified startup baseline**
- 4608 — probe
- 5120 — probe
- 5632 — edge probe

6144 and 8192 are removed from the normal selector. If an upgraded Build 77 installation still has 6144 or 8192 persisted, Build 78 migrates that value to 4096 before API startup.

## Capacity mode

The frozen Phase2F path uses 32x32 prefill.

Build 78 keeps 32x32 at 4096 and below. For any context above 4096 it caps:

- batch = 16
- uBatch = 16

This reduces context-create/compute-buffer peak pressure while preserving the rest of the Full/Accelerated runtime configuration. Metal Tensor remains disabled.

## Test order

1. 4608
2. 5120
3. 5632

Stop at the first tier that terminates the app or fails context creation. The highest preceding tier becomes the current device capacity candidate.

Do not retry 6144/8192 in this build.
