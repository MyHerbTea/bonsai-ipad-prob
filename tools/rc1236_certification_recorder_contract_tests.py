from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
recorder = (root / "BonsaiLab" / "CertificationRunRecorder.swift").read_text()
view = (root / "BonsaiLab" / "ProductionView.swift").read_text()
project = (root / "project.yml").read_text()
workflow = (root / ".github" / "workflows" / "build-ios.yml").read_text()

# Build 49 adds an on-device, crash-resilient, single-file certification archive.
assert "final class CertificationRunRecorder" in recorder
assert "BONSAI-RUN-" in recorder
assert "bonsai_certification_active.json" in recorder
assert "Application Support" not in recorder  # path is generated via FileManager API
assert "status = \"interrupted\"" in recorder
assert "recoverInterruptedRunIfNeeded" in recorder
assert "app_recovered_interrupted_run" in recorder
assert "bonsai_engine_stage.txt" in recorder
assert "bonsai_staged_vision_stage.txt" in recorder
assert "bonsai_two_phase_vision_stage.txt" in recorder
assert "bonsai_mlx_vision_stage.txt" in recorder
assert "bonsai_mlx_injection_stage.txt" in recorder
assert "bonsai_api_preflight.txt" in recorder
assert "recordEvent" in recorder
assert "recordSnapshot" in recorder
assert "finishRun" in recorder

# The archive must be JSON and retain privacy boundaries.
assert "JSONEncoder" in recorder
assert "schemaVersion" in recorder
assert "api_key" not in recorder
assert "base64" not in recorder
assert "prompt_text" not in recorder
assert "assistant_output" not in recorder

# ProductionView wires the recorder but does not change the frozen runtime.
assert "@StateObject private var certificationRecorder" in view
assert (
    'Section("RC1.23.6 Certification Recorder")' in view
    or 'Section("RC1.23.6 Restart Certification")' in view
)
assert "ShareLink" in view
assert "recoverInterruptedRunIfNeeded()" in view
assert "buildDiagnosticSnapshot()" in view

# Runtime invariants remain unchanged.
assert re.search(r'apiRuntime\.batch\s*=\s*8', view)
assert re.search(r'apiRuntime\.ubatch\s*=\s*8', view)
assert 'apiRuntimeProfile == "safe"' in view
assert "n_seq_max" not in view  # remains owned by BonsaiEngine/native runtime
assert 'private var apiContextProfile = "512"' in view
assert 'Text("256 Experimental")' not in view
assert '"实验：API Context"' not in view
assert re.search(
    r'if\s+apiContextProfile\s*!=\s*"512"\s*\{\s*'
    r'apiContextProfile\s*=\s*"512"',
    view,
)
assert re.search(
    r'let\s+selectedAPIContext\s*=\s*512',
    view,
)

# Build 49+ retains the recorder and CI coverage.
build_match = re.search(
    r'CURRENT_PROJECT_VERSION:\s*"(?P<build>\d+)"',
    project,
)
assert build_match is not None
assert int(build_match.group("build")) >= 49
assert "RC1.23.6 certification recorder contracts" in workflow
assert "tools/rc1236_certification_recorder_contract_tests.py" in workflow

print("RC1.23.6 Build 49 certification recorder contracts: PASS")
