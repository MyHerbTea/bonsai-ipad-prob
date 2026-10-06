# RC1.26 Build 70 — Phase 2C-0 Device Evidence

Captured on device: 2026-10-06 12:08 +08:00.

## Identity

- Build ID: `rc1.26-build70-metal-prefill-measurement`
- Build: `70`
- Frozen baseline commit: `0d84e106daa10590ddbd1b7a3b6b3212114db6f7`
- Last certified pre-Phase-2C source: Build 68 `eb58c13626d28b1854519a485e5355418d3f5591`
- Prism release: `prism-b10743-adfffbe`
- Prism source: `adfffbe41b2cabcd51fff326ab045662265062bb`
- Prism XCFramework SHA-256: `d23bb0325cca43054c1a76a233c79950a1ce26d98a359466c8d81fafd3b1d9ad`

## Result

**PASS_CAPABILITY_AVAILABLE**

The corrected v2 capability probe reported:

- Apple M5 GPU present.
- Metal 4 family supported.
- Metal language 4 requested.
- `<metal_tensor>` library compiled.
- Metal Tensor pipeline compiled.
- Prism Metal registry present.
- `EMBED_LIBRARY=1`.
- `candidate_probe_eligible=true`.
- `failure_stage=0`.
- `error_code=0`.
- Probe duration: 526,666 ns (~0.527 ms).

## Safety state

The device remained on the frozen baseline workaround during this capability audit:

- `GGML_METAL_TENSOR_DISABLE=1`.
- `metal_tensor_prefill_effective=false`.
- `runtime_toggle_safe=false`.
- Effective runtime profile remained `BASELINE`.
- No behavior-changing runtime flag was effective.

Therefore this evidence proves **capability only**. It does not prove that a Bonsai inference graph dispatched Metal Tensor operations.

## Phase 2C-1 gate

Phase 2C-0 is closed. Phase 2C-1 may proceed only with a fresh-process launch-latched A/B design:

1. BASELINE process starts with `GGML_METAL_TENSOR_DISABLE=1`.
2. CANDIDATE process starts with the variable unset.
3. The launch arm is immutable for the process lifetime.
4. Switching arms requires a full app process restart.
5. The active Prism backend state must be evidenced from its real initialization path.
6. Phase 2C-1 remains a viability probe; promotion requires later controlled ABABAB evidence and the established performance/safety gates.
