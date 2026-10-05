from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
runtime = (ROOT / "BonsaiLab/RuntimeOptimization.swift").read_text(encoding="utf-8")
server = (ROOT / "BonsaiLab/LocalOpenAIServer.swift").read_text(encoding="utf-8")
header = (ROOT / "BonsaiLab/SystemProbeBridge.h").read_text(encoding="utf-8")
impl = (ROOT / "BonsaiLab/SystemProbeBridge.mm").read_text(encoding="utf-8")

for marker in [
    "RuntimeHeapPressureReliefRecord",
    "heapPressureRelief",
    "MemoryPressureGrade",
]:
    assert marker in runtime, marker

for marker in [
    "BonsaiRelieveHeapPressure",
    "malloc_zone_pressure_relief(NULL, 0)",
    "#include <malloc/malloc.h>",
]:
    assert marker in header + "\n" + impl, marker

for marker in [
    'request.path == "/debug/gc-or-trim"',
    '"RC1.26_PHASE2B_HEAP_PRESSURE_RELIEF"',
    '"bb.heapPressureRelief_requires_bb.governor.metalAware"',
    'assessment.grade == .constrained',
    'assessment.grade == .critical',
    '"automatic_request_end"',
    '"debug_gc_or_trim"',
    '"pressure_below_threshold"',
    '"bytes_released"',
    '"duration_ms"',
]:
    assert marker in server, marker

# The Phase 2B actuator must reclaim allocator slack only. It must not
# unload the resident model, clear llama semantic memory, or mutate MLX
# model state from the server control plane.
server_relief = server[server.index("private func performHeapPressureRelief"):]
assert "BonsaiReleaseStagedResidentModel" not in server_relief
assert "llama_memory_clear" not in server_relief
assert "Memory.clearCache()" not in server_relief

print("RC1.26 Phase 2B heap pressure relief contracts: PASS")
