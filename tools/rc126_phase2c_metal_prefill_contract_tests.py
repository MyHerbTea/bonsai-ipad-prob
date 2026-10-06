from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
engine = (ROOT / "BonsaiLab/BonsaiEngine.swift").read_text(encoding="utf-8")
types = (ROOT / "BonsaiLab/LabTypes.swift").read_text(encoding="utf-8")
server = (ROOT / "BonsaiLab/LocalOpenAIServer.swift").read_text(encoding="utf-8")
bridge_h = (ROOT / "BonsaiLab/SystemProbeBridge.h").read_text(encoding="utf-8")
bridge_mm = (ROOT / "BonsaiLab/SystemProbeBridge.mm").read_text(encoding="utf-8")

for marker in ["let prefillSeconds: Double", "let decodeToFirstTokenSeconds: Double"]:
    assert marker in types, marker

for marker in [
    "let prefillEnd = DispatchTime.now().uptimeNanoseconds",
    "let prefillSeconds =",
    "let decodeToFirstTokenSeconds =",
    "prefillSeconds: prefillSeconds",
    "decodeToFirstTokenSeconds:",
]:
    assert marker in engine, marker

for marker in [
    "BonsaiMetalTensorCapabilityProbe",
    "BonsaiProbeMetalTensorCapability",
    "tensor_pipeline_compiled",
    "framework_embed_library",
]:
    assert marker in bridge_h, marker

for marker in [
    '#include <metal_tensor>',
    "MTLLanguageVersion) (4u << 16)",
    "supportsFamily:(MTLGPUFamily) 5002",
    "newComputePipelineStateWithFunction",
    'ggml_backend_reg_by_name("MTL")',
    '"ggml_backend_get_features"',
    '"EMBED_LIBRARY"',
    "auto sA = a.slice(0, 0);",
    "auto sB = b.slice(0, 0);",
    "mm.run(sB, sA, dst);",
]

assert "mm.run(b.slice(" not in bridge_mm:
    assert marker in bridge_mm, marker

for marker in [
    'request.path == "/debug/prefill"',
    "RuntimePrefillObservation",
    "recordPrefillObservation(result)",
    '"RC1.26_PHASE2C0_CAPABILITY_PROVENANCE_AUDIT"',
    '"rc126.phase2c0.metal-tensor-capability.v2"',
    '"metal_tensor_prefill_requested":',
    '"metal_tensor_prefill_effective": false',
    '"capability_only_backend_latched"',
    '"fresh_process_backend_init_required"',
    '"candidate_probe_eligible":',
    '"runtime_toggle_safe": false',
    '"llama_backend_free_unloads_registry": false',
    '"prism-b10743-adfffbe"',
    '"adfffbe41b2cabcd51fff326ab045662265062bb"',
    '"d23bb0325cca43054c1a76a233c79950a1ce26d98a359466c8d81fafd3b1d9ad"',
]:
    assert marker in server, marker

assert 'setenv("GGML_METAL_TENSOR_DISABLE", "1", 1)' in engine
assert "effective.metalTensorPrefill = true" not in server
assert "lastHeapPressureRelief = nil" in server

print("RC1.26 Phase 2C-0 Metal Tensor capability/provenance contracts: PASS")
