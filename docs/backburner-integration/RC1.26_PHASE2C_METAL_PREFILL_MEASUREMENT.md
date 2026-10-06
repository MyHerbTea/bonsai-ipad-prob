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

## Build 69 device result and Build 70 correction

The 2026-10-06 Build 69 device audit returned `PASS_CAPABILITY_UNAVAILABLE` on Apple M5 GPU with Metal family 4 supported, Prism Metal registry present, and `EMBED_LIBRARY=1`. The failure was isolated to stage 3 (`MTLLibraryErrorCompileFailure`): the probe passed temporary `slice(...)` values directly to `matmul2d::run` even though its operands are thread references. This was a probe-source defect, not evidence that the M5 lacks Metal Tensor capability.

Build 70 preserves Build 69 evidence and corrects only the probe shader by materializing the operand slices as local lvalues before `run`. Its implementation id is `rc126.phase2c0.metal-tensor-capability.v2`. No inference behavior, frozen baseline, resident runtime, or Vision path is enabled or promoted by this correction.

## Build 70 device closure

Build 70 device evidence captured on 2026-10-06 returned `PASS_CAPABILITY_AVAILABLE`:

- Apple M5 GPU / Metal 4 supported.
- Tensor library and Tensor pipeline both compiled.
- Prism registry present with `EMBED_LIBRARY=1`.
- `candidate_probe_eligible=true`.
- `failure_stage=0`, `error_code=0`.
- Capability probe duration was approximately 0.527 ms.
- The process remained BASELINE with `GGML_METAL_TENSOR_DISABLE=1` and `metal_tensor_prefill_effective=false`.

The authoritative device record is `RC1.26_BUILD70_PHASE2C0_DEVICE_EVIDENCE.md`.

## Phase 2C-1 fresh-backend viability

Phase 2C-1 uses a process-immutable launch arm:

- `BASELINE`: start the process with `GGML_METAL_TENSOR_DISABLE=1`.
- `CANDIDATE`: start the process with the variable unset.
- Scheduling another arm only affects the next process.
- Switching arms requires a complete app restart.
- Any in-process attempt to change the arm after the first backend registry initialization is rejected.

Build 71 also captures the pinned Prism backend initialization log and requires the real backend line `has tensor = false` for BASELINE and `has tensor = true` for CANDIDATE. This proves the active backend's Tensor API state without replacing the pinned Prism XCFramework. It still does not claim that every prefill graph dispatched a Tensor kernel.

The first Phase 2C-1 device gate is a two-arm fresh-process viability smoke (one warm-up plus three token-identical measured requests per arm). Only a promising, safe result advances to the controlled ABABAB gate.

Promotion still requires the handoff thresholds: token-identical controlled A/B, repeatable prefill/TTFT gain, decode regression within budget, no crash/jetsam/hang, no silent fallback, and no resident-runtime or Vision regression.


## Phase 2C-1 device closure — Build 71

The 2026-10-06 fresh-process device A/B is complete. Build 71 proved the backend mechanism itself: BASELINE captured `has tensor = false`; CANDIDATE captured `has tensor = true`; process launch IDs differed; runtime switching remained forbidden.

The controlled 1658-token workload produced:

- BASELINE avg prefill: 254,616.111 ms.
- CANDIDATE avg prefill: 263,672.050 ms (**3.557% slower**).
- BASELINE avg TTFT: 255,195.273 ms.
- CANDIDATE avg TTFT: 264,247.221 ms (**3.547% slower**).
- Decode-to-first improved only 0.689%.
- Decode throughput improved only 0.472%.
- Metal allocated/headroom deltas were identical (+256 KiB / -256 KiB).
- BASELINE ended thermal `nominal`; CANDIDATE ended `fair`.

Decision: **PASS_MECHANISM / FAIL_PERFORMANCE_GATE / CLOSE_PHASE2C_NO_PROMOTION**.

Do not proceed to ABABAB or the context ladder. Metal Tensor remains experimental and must not enter the ACCELERATED/production profile. The detailed device record is `RC1.26_BUILD71_PHASE2C1_DEVICE_EVIDENCE.md`.
