from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
server = (ROOT / "BonsaiLab/LocalOpenAIServer.swift").read_text(encoding="utf-8")
runtime = (ROOT / "BonsaiLab/RuntimeOptimization.swift").read_text(encoding="utf-8")

for marker in [
    'request.path == "/debug/build"',
    'request.path == "/debug/runtime"',
    'request.path == "/debug/telemetry"',
    'request.path == "/debug/governor"',
    'request.path == "/debug/runtime/profile"',
    '"behavior_changes_enabled":',
    '"profile": state.profile.rawValue',
    '"phase": "RC1.26_PHASE2A_MEMORY_GOVERNOR_OBSERVER"',
    '"unknown_runtime_flag"',
    "RuntimeTelemetrySnapshot.capture(",
    "effectiveRuntimeState()",
]:
    assert marker in server, marker

auth_index = server.index("guard authorized(request) else")
debug_index = server.index('request.path == "/debug/build"')
models_index = server.index('request.path == "/v1/models"')
assert auth_index < debug_index < models_index

for marker in [
    '"bb.telemetry.extended"',
    '"bb.governor.metalAware"',
    '"bb.heapPressureRelief"',
    '"bb.metalTensor.prefill"',
    '"bb.metalFusion.experimental"',
    '"bb.lazyEmbedding"',
    '"bb.prefixStateCache"',
    '"bb.tieredKV"',
    '"bb.tieredKV.quantizedCold"',
    '"bb.aneColdKV"',
    '"bb.speculative.experimental"',
    "static let baseline = RuntimeFeatureFlags()",
]:
    assert marker in runtime, marker

for marker in [
    "var metalAwareGovernor = false",
    "var heapPressureRelief = false",
    "var metalTensorPrefill = false",
    "var metalFusionExperimental = false",
    "var lazyEmbedding = false",
    "var prefixStateCache = false",
    "var tieredKV = false",
    "var tieredKVQuantizedCold = false",
    "var aneColdKV = false",
    "var speculativeExperimental = false",
]:
    assert marker in runtime, marker

print("RC1.26 automation control contracts: PASS")
