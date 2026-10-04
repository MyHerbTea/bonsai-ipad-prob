from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
server = (root / "BonsaiLab" / "LocalOpenAIServer.swift").read_text()
view = (root / "BonsaiLab" / "ProductionView.swift").read_text()
project = (root / "project.yml").read_text()
workflow = (root / ".github" / "workflows" / "build-ios.yml").read_text()

# Local server must support restarting the listener while preserving the
# existing handler closure and therefore the resident model/context.
assert "func restartListenerPreservingHandler(" in server
assert "let preservedHandler = handler" in server
assert "guard let preservedHandler" in server
assert "handler: preservedHandler" in server
assert (
    "try start(" in server
    or "try installListener(" in server
)

# Build 52 runner: cycle 1 performs one full runtime load, cycles 2+ restart
# only the listener/handler and MUST NOT unload/recreate the engine.
assert "Resident Runtime Restart" in view or "listener_restart_resident_runtime" in view
assert "listener_restart_resident_runtime" in view
assert "full_runtime_load" in view
assert "restartListenerPreservingHandler" in view
assert "resident_restart_requested" in view
assert "resident_restart_ready" in view

runner_start = view.index("private func runRestartCertification()")
runner_end = view.index(
    "private func waitForCertificationAPIReady",
    runner_start,
)
runner = view[runner_start:runner_end]

# The full engine teardown/load is allowed only in the cycle-1 branch.
assert "if cycle == 1" in runner
assert "startAPIServer()" in runner
assert (
    "restartListenerPreservingHandler" in runner
    or "resumeAPIListenerPreservingRuntime()" in runner
)
assert runner.index("if cycle == 1") < runner.index("startAPIServer()")

# No rejected dynamic-context experiment returns.
assert 'private var apiContextProfile = "512"' in view
assert 'Text("256 Experimental")' not in view
assert re.search(r'let\s+selectedAPIContext\s*=\s*512', view)
assert 'apiRuntimeProfile = "accelerated"' in runner
assert "visionPrefixKVReuseEnabled = true" in runner

# Same controlled OpenAI request and one-file recorder are retained.
assert 'http://127.0.0.1:8080/v1/chat/completions' in view
assert '"max_completion_tokens": 128' in view
assert '"stream": false' in view
assert '"reasoning_effort": "none"' in view
assert "certificationRecorder.finishRun(" in view
assert 'Label("分享最近测试结果"' in view

# Build 52+ retains resident-runtime restart behavior.
build_match = re.search(
    r'CURRENT_PROJECT_VERSION:\s*"(?P<build>\d+)"',
    project,
)
assert build_match is not None
assert int(build_match.group("build")) >= 52
assert "RC1.23.6 resident runtime restart contracts" in workflow
assert "tools/rc1236_resident_runtime_restart_contract_tests.py" in workflow

print("RC1.23.6 Build 52 resident runtime restart contracts: PASS")
