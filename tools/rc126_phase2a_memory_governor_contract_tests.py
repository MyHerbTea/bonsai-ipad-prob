from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
runtime = (ROOT / "BonsaiLab/RuntimeOptimization.swift").read_text(encoding="utf-8")
server = (ROOT / "BonsaiLab/LocalOpenAIServer.swift").read_text(encoding="utf-8")

assert (
    '"build_id": "rc1.26-build67-request-lifecycle-governor-observer"' in server
    or '"build_id": "rc1.26-build68-heap-pressure-relief"' in server
    or '"build_id": "rc1.26-build69-metal-prefill-measurement"' in server
    or '"build_id": "rc1.26-build70-metal-prefill-measurement"' in server
    or '"build_id": "rc1.26-build71-fresh-backend-metal-tensor-ab"' in server
    or '"build_id": "rc1.26-build72-prefill-batch-8-vs-16"' in server
    or '"build_id": "rc1.26-build75-api-cold-start-guard"' in server
    or '"build_id": "rc1.26-build76-text-kv-reuse-lab"' in server
    or '"build_id": "rc1.26-build77-extended-context-lab"' in server
    or '"build_id": "rc1.26-build78-context-boundary-lab"' in server
    or '"build_id": "rc1.26-build79-storage-memory-long-context-lab"' in server
    or '"build_id": "rc1.26-build80-long-context-tier-reload-fix"' in server
    or '"build_id": "rc1.26-build81-32k-memory-squeeze"' in server
    or '"build_id": "rc1.26-build82-unified-metal-32k-lab"' in server
)

for marker in [
    "enum MemoryPressureGrade",
    "struct MemoryGovernorAssessment",
    "struct RuntimeGovernorBoundaryRecord",
    "metal_headroom_lt_25pct",
    "metal_headroom_lt_12_5pct",
    "metal_headroom_lt_5pct",
    "available_lt_2048mib",
    "available_lt_1024mib",
    "available_lt_512mib",
    'action = "observe"',
    'action = "eligible_for_heap_pressure_relief"',
    'action = "block_optional_growth_and_relieve"',
]:
    assert marker in runtime, marker

behavior_start = runtime.index("var hasBehaviorChangingFeature: Bool")
behavior_slice = runtime[behavior_start:behavior_start + 500]
assert "heapPressureRelief" in behavior_slice
assert "metalAwareGovernor" not in behavior_slice

for marker in [
    'request.path == "/debug/governor"',
    '"observer_active"',
    '"actuator_enabled":',
    '"bb.heapPressureRelief"',
    '"RC1.26_PHASE2B_HEAP_PRESSURE_RELIEF"',
    "effective.metalAwareGovernor",
    '"API_REQUEST_BEGIN"',
    '"API_REQUEST_END"',
    '"request_observation_sequence"',
]:
    assert marker in server, marker

assert "BonsaiReleaseStagedResidentModel" not in runtime
assert "Memory.clearCache()" not in runtime
assert "llama_memory_clear" not in runtime

print("RC1.26 Phase 2A memory governor contracts: PASS")
