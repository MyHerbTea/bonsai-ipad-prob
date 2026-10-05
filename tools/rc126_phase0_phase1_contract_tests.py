from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]

manifest = json.loads(
    (ROOT / "docs/backburner-integration/BASELINE_MANIFEST.json")
    .read_text(encoding="utf-8")
)
assert manifest["source_commit"] == "0d84e106daa10590ddbd1b7a3b6b3212114db6f7"
assert manifest["device_certification"]["overall"] == "PASS"
assert manifest["device_certification"]["crash_observed"] is False
assert manifest["device_certification"]["recovery_count"] == 0
assert manifest["device_certification"]["release_freeze_gate_candidate"] == "PASS"

flags = (ROOT / "BonsaiLab/RuntimeOptimization.swift").read_text(encoding="utf-8")
for marker in [
    'case baseline = "BASELINE"',
    "static let baseline = RuntimeFeatureFlags()",
    "var extendedTelemetry = true",
    "var metalAwareGovernor = false",
    "var heapPressureRelief = false",
    "var metalTensorPrefill = false",
    "var tieredKV = false",
    "var aneColdKV = false",
    "var speculativeExperimental = false",
    "RuntimeTelemetrySnapshot",
    "metalRecommendedWorkingSetBytes",
    "thermalState",
]:
    assert marker in flags, marker

header = (ROOT / "BonsaiLab/SystemProbeBridge.h").read_text(encoding="utf-8")
impl = (ROOT / "BonsaiLab/SystemProbeBridge.mm").read_text(encoding="utf-8")
for marker in [
    "metal_allocated_bytes",
    "metal_recommended_bytes",
    "has_unified_memory",
]:
    assert marker in header, marker
assert "MTLCreateSystemDefaultDevice" in impl
assert "currentAllocatedSize" in impl
assert "recommendedMaxWorkingSetSize" in impl
assert "hasUnifiedMemory" in impl

print("RC1.26 Phase 0 + Phase 1 contracts: PASS")
