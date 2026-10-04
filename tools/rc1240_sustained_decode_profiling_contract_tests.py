from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
view = (root / "BonsaiLab" / "ProductionView.swift").read_text()
project = (root / "project.yml").read_text()
workflow = (root / ".github" / "workflows" / "build-ios.yml").read_text()
engine = (root / "BonsaiLab" / "BonsaiEngine.swift").read_text()

# RC1.24.0 Build 55 is instrumentation-only. It must preserve the frozen
# Build 54 inference/runtime configuration while adding per-request evidence
# for sustained decode degradation.
assert 'Text("1.0 · RC1.24.0 Sustained Decode Profiling")' in view
assert "[RC1.24.0 SUSTAINED DECODE REQUEST HISTORY]" in view

# Per-request CPU and lifecycle observability.
for marker in [
    "ProcessCPUSnapshot",
    "processCPUSnapshot()",
    '"process_cpu_user_ms="',
    '"process_cpu_system_ms="',
    '"process_cpu_total_ms="',
    '"process_cpu_percent_estimate="',
    '"active_processor_count="',
    '"app_scene_phase_start="',
    '"app_scene_phase_end="',
    "BonsaiRC1240AppScenePhase",
]:
    assert marker in view

# Resource snapshots must be captured at request start and end so repeated
# requests can be compared without changing the inference path.
for marker in [
    "requestResourceSnapshotStart",
    "resourceSnapshotStart:",
    "resourceTransitionLines(",
    '"available_mib_start="',
    '"resident_mib_start="',
    '"phys_footprint_mib_start="',
    '"metal_allocated_mib_start="',
]:
    assert marker in view

# Existing long-run and request metrics remain present.
for marker in [
    '"request_ordinal=',
    '"session_elapsed_start_ms="',
    '"session_elapsed_end_ms="',
    '"thermal_state_start="',
    '"thermal_state_end="',
    '"decode_ms="',
    '"tokens_per_second="',
]:
    assert marker in view

# Frozen Build 54 runtime behavior is unchanged.
assert re.search(r'let\s+selectedAPIContext\s*=\s*512', view)
assert re.search(r'apiRuntime\.batch\s*=\s*8', view)
assert re.search(r'apiRuntime\.ubatch\s*=\s*8', view)
assert 'apiRuntime.kvUnified = true' in view
assert 'apiRuntime.loadMode = .mmap' in view
assert 'generateCachedVision(' in engine
assert 'generateText(' in engine

# Build and CI identity.
assert re.search(r'CURRENT_PROJECT_VERSION:\s*"55"', project)
assert "lab-v1-rc1-24-0-sustained-decode-profiling" in workflow
assert "RC1.24.0 sustained decode profiling contracts" in workflow
assert "tools/rc1240_sustained_decode_profiling_contract_tests.py" in workflow
assert 'CFBundleVersion raw -o - "$APP/Info.plist")" = "55"' in workflow
assert "Build55-Sustained-Decode-Profiling" in workflow

print("RC1.24.0 Build 55 sustained decode profiling contracts: PASS")
