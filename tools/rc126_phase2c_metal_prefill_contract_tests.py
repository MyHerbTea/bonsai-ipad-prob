from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
engine = (ROOT / "BonsaiLab/BonsaiEngine.swift").read_text(encoding="utf-8")
types = (ROOT / "BonsaiLab/LabTypes.swift").read_text(encoding="utf-8")
server = (ROOT / "BonsaiLab/LocalOpenAIServer.swift").read_text(encoding="utf-8")
view = (ROOT / "BonsaiLab/ProductionView.swift").read_text(encoding="utf-8")

for marker in ["let prefillSeconds: Double","let decodeToFirstTokenSeconds: Double"]:
    assert marker in types, marker

for marker in ["let prefillEnd = DispatchTime.now().uptimeNanoseconds","let prefillSeconds =","let decodeToFirstTokenSeconds =","prefillSeconds: prefillSeconds","decodeToFirstTokenSeconds:"]:
    assert marker in engine, marker

for marker in ["prefill_ms=","decode_to_first_token_ms="]:
    assert marker in view, marker

for marker in [
    'request.path == "/debug/prefill"',
    "RuntimePrefillObservation",
    "recordPrefillObservation(result)",
    '"RC1.26_PHASE2C_METAL_PREFILL_MEASUREMENT"',
    '"metal_tensor_prefill_effective":',
    '"measurement_only_frozen_workaround"',
    '"ggml_metal_tensor_disable"',
    '"ttft_reconstruction_error_ms"',
    '"build_id": "rc1.26-build69-metal-prefill-measurement"',
]:
    assert marker in server, marker

assert 'setenv("GGML_METAL_TENSOR_DISABLE", "1", 1)' in engine
assert "effective.metalTensorPrefill = true" not in server
assert "lastHeapPressureRelief = nil" in server

print("RC1.26 Phase 2C Metal prefill measurement contracts: PASS")
