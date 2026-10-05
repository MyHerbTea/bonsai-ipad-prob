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
assert (
    'Text("1.0 · RC1.24.0 Sustained Decode Profiling")' in view
    or 'Text("1.0 · RC1.24.1 Runtime Profile A/B")' in view
    or 'Text("1.0 · RC1.25.0 Multi-Image OpenAI API")' in view
    or 'Text("1.0 · RC1.25.1 API Hardening")' in view
    or 'Text("1.0 · RC1.25.2 API Usability")' in view
)
assert "[RC1.24.0 SUSTAINED DECODE PROFILING]" in view
assert "[RC1.23.3 LONG-RUN REQUEST HISTORY]" in view

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
    '"available_mib",',
    '"resident_mib",',
    '"phys_footprint_mib",',
    '"metal_allocated_mib",',
    'key + "_start="',
    'key + "_end="',
    'key + "_delta="',
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

# Sustained analysis needs the new evidence in every successful history row,
# not only in the latest-request snapshot.
vision_start = view.index("static func persistVisionSuccess(")
text_start = view.index("static func persistTextSuccess(", vision_start)
summary_start = view.index("static func visionSummary(", text_start)
vision_block = view[vision_start:text_start]
text_block = view[text_start:summary_start]
for block in [vision_block, text_block]:
    history_start = block.index("appendLongRunHistory([")
    history = block[history_start:]
    assert "profilingLines(" in history
    assert "resourceTransitionLines(" in history
    assert "resourceSnapshotStart" in history

failure_start = view.index("static func persistFailure(")
failure_end = view.index("static func persistVisionSuccess(", failure_start)
failure_block = view[failure_start:failure_end]
failure_history = failure_block[failure_block.index("appendLongRunHistory(["):]
assert "profilingLines(" in failure_history

# Frozen runtime mechanics are unchanged. RC1.25.2 explicitly evolves only
# the product context selector; batch/uBatch and the accelerated path remain.
if "RC1.25.2 API Usability" in view:
    assert 'Int(apiContextProfile) ?? 512' in view
    assert '"512", "768", "1024", "2048"' in view
else:
    assert re.search(r'let\s+selectedAPIContext\s*=\s*512', view)
assert re.search(r'apiRuntime\.batch\s*=\s*8', view)
assert re.search(r'apiRuntime\.ubatch\s*=\s*8', view)
assert 'apiRuntime.kvUnified = true' in view
assert 'apiRuntime.loadMode = .mmap' in view
assert 'generateCachedVision(' in engine
assert 'generateText(' in engine

# Build and CI identity.
build_match = re.search(r'CURRENT_PROJECT_VERSION:\s*"(?P<build>\d+)"', project)
assert build_match is not None
assert int(build_match.group("build")) >= 55
assert "lab-v1-rc1-24-0-sustained-decode-profiling" in workflow
assert "RC1.24.0 sustained decode profiling contracts" in workflow
assert "tools/rc1240_sustained_decode_profiling_contract_tests.py" in workflow
assert "tools/rc1240_sustained_decode_profiling_contract_tests.py" in workflow

print("RC1.24.0 Build 55 sustained decode profiling contracts: PASS")
