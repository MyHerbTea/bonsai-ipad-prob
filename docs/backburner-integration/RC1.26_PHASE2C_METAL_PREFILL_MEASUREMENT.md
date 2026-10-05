# RC1.26 Phase 2C-0 — Metal Tensor Capability / Provenance Audit

Phase 2C-0 is a capability/provenance gate. It does not promote or enable `bb.metalTensor.prefill`.

## Frozen and certified boundaries

- Frozen baseline: RC1.25.3 Build 64, `0d84e106daa10590ddbd1b7a3b6b3212114db6f7`.
- Last device-certified binary source before this gate: Build 68, `eb58c13626d28b1854519a485e5355418d3f5591`.
- Phase 2B remains `PASS / SAFE_NO_RECLAIM_OBSERVED`, EXPERIMENTAL only.

## Pinned native provenance

- Prism release: `prism-b10743-adfffbe`.
- Prism source: `adfffbe41b2cabcd51fff326ab045662265062bb`.
- XCFramework SHA-256: `d23bb0325cca43054c1a76a233c79950a1ce26d98a359466c8d81fafd3b1d9ad`.

No framework replacement is permitted in 2C-0.

## Lifecycle finding

The pinned Prism Metal backend reads `GGML_METAL_TENSOR_DISABLE` while creating its Metal device capability state. Bonsai initializes llama backends once and keeps the backend registry resident. In this pinned source, `llama_backend_free()` does not unload the backend registry.

Therefore changing the environment variable after the first `llama_backend_init()` is not a valid Metal Tensor A/B switch. Build 69 must report `metal_tensor_prefill_effective=false` even when the flag is requested.

## Build 69 capability probe

`GET /debug/prefill` now reports exact provenance and performs a real runtime probe:

1. verify a Metal device;
2. verify Metal family 4 using the pinned Prism ABI value;
3. request Metal language version 4.0;
4. compile source importing `<metal_tensor>`;
5. create a Metal Tensor matmul compute pipeline;
6. query the loaded Prism Metal registry for the public `EMBED_LIBRARY` feature.

The endpoint also reports `candidate_probe_eligible`, failure stage/error code, probe duration, the frozen environment variable, and explicit backend-latch semantics.

This proves API/compiler/pipeline capability. It deliberately does not claim that a real Bonsai graph dispatched a Tensor kernel.

## Phase 2C-1 entry gate

A performance experiment is allowed only after Build 69 reports the capability checks available. The candidate must then be initialized from a fresh backend/process state, or a later native hook must directly prove the active Prism backend state. A post-init environment-variable flip is forbidden.

Promotion still requires the handoff thresholds: token-identical controlled A/B, repeatable prefill/TTFT gain, decode regression within budget, no crash/jetsam/hang, no silent fallback, and no resident-runtime or Vision regression.
