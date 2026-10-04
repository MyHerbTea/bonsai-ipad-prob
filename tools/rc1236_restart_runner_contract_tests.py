from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
view = (root / "BonsaiLab" / "ProductionView.swift").read_text()
recorder = (root / "BonsaiLab" / "CertificationRunRecorder.swift").read_text()
project = (root / "project.yml").read_text()
workflow = (root / ".github" / "workflows" / "build-ios.yml").read_text()

# One-click UI and fixed 512-only test contract.
assert 'Button("运行 Restart Certification")' in view
assert "runRestartCertification()" in view
assert "certificationRunnerRunning" in view
assert "certificationRunnerProgress" in view
assert "let certificationCycles = 4" in view
assert "let selectedAPIContext = 512" in view
assert 'private var apiContextProfile = "512"' in view
assert 'Text("256 Experimental")' not in view

# Runner uses the actual local OpenAI endpoint via loopback.
assert 'http://127.0.0.1:8080/v1/chat/completions' in view
assert '"max_completion_tokens": 128' in view
assert '"stream": false' in view
assert '"reasoning_effort": "none"' in view
assert "Describe the person, the dog, and the background in this image using concise bullet points." in view

# Each cycle records lifecycle events, seed/warm results and a diagnostic snapshot.
for marker in [
    "cycle_started",
    "api_stop_requested",
    "engine_unload_started",
    "engine_unload_finished",
    "api_start_requested",
    "api_ready",
    "seed_request_finished",
    "warm_request_finished",
    "cycle_completed",
]:
    assert marker in view

assert "recordSnapshot(" in view
assert 'label: "cycle_\\(cycle)_warm_snapshot"' in view

# Test setup must require model + Vision Tower + image and must not require mmproj.
assert re.search(
    r'guard\s+let\s+modelURL,\s*'
    r'let\s+mlxVisionWeightsURL,\s*'
    r'let\s+imageURL',
    view,
    flags=re.S,
)
runner_start = view.index("private func runRestartCertification()")
runner_end = view.index(
    "private func waitForCertificationAPIReady",
    runner_start,
)
runner_body = view[runner_start:runner_end]
assert "mmprojURL" not in runner_body

# Teardown is awaited inside the runner.
assert re.search(
    r'apiServer\.stop\(\)[\s\S]*?'
    r'await\s+engine\.unloadAll\(\)',
    view,
)

# Runner automatically starts/finalizes the persistent recorder.
assert "certificationRecorder.startRun(" in view
assert "certificationRecorder.finishRun(" in view
assert "certificationRecorder.recordEvent(" in view
assert "certificationRecorder.recordSnapshot(" in view
assert "BONSAI-RUN-" in recorder

# Build 50+ retains the one-click restart runner.
build_match = re.search(
    r'CURRENT_PROJECT_VERSION:\s*"(?P<build>\d+)"',
    project,
)
assert build_match is not None
assert int(build_match.group("build")) >= 50
assert "RC1.23.6 restart runner contracts" in workflow
assert "tools/rc1236_restart_runner_contract_tests.py" in workflow

print("RC1.23.6 Build 50 one-click restart runner contracts: PASS")
