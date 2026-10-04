from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
server = (root / "BonsaiLab" / "LocalOpenAIServer.swift").read_text()
view = (root / "BonsaiLab" / "ProductionView.swift").read_text()
project = (root / "project.yml").read_text()
workflow = (root / ".github" / "workflows" / "build-ios.yml").read_text()

# Build 53 must await old-listener cancellation before rebinding the same port.
assert "func restartListenerPreservingHandler(" in server
assert "async throws" in server[
    server.index("func restartListenerPreservingHandler("):
    server.index("func stop()", server.index("func restartListenerPreservingHandler("))
]
assert "cancelListenerForRestart" in server
assert "withCheckedContinuation" in server
assert ".cancelled" in server
assert "listenerGeneration" in server
assert re.search(
    r'guard\s+self\.listenerGeneration\s*==\s*generation\s*'
    r'else\s*\{\s*return\s*\}',
    server,
    flags=re.S,
)

restart_start = server.index("func restartListenerPreservingHandler(")
restart_end = server.index("func stop()", restart_start)
restart = server[restart_start:restart_end]
assert "await cancelListenerForRestart()" in restart
assert "try installListener(" in restart
assert restart.index("await cancelListenerForRestart()") < restart.index("try installListener(")

# Normal start and soft restart share a single listener-install path.
assert "private func installListener(" in server
assert "try installListener(" in server
assert "allowLocalEndpointReuse = true" in server

# Runner must await the soft restart and retain the resident-runtime strategy.
runner_start = view.index("private func runRestartCertification()")
runner_end = view.index(
    "private func waitForCertificationAPIReady",
    runner_start,
)
runner = view[runner_start:runner_end]
assert "try await apiServer" in runner
assert ".restartListenerPreservingHandler(" in runner
assert '"listener_restart_resident_runtime"' in runner
assert "if cycle == 1" in runner

# Frozen inference behavior remains unchanged.
assert 'private var apiContextProfile = "512"' in view
assert 'Text("256 Experimental")' not in view
assert re.search(r'let\s+selectedAPIContext\s*=\s*512', view)
assert 'apiRuntimeProfile = "accelerated"' in runner
assert "visionPrefixKVReuseEnabled = true" in runner

# Single-file recorder/export remains the user-facing test workflow.
assert "certificationRecorder.finishRun(" in view
assert 'Label("分享最近测试结果"' in view
assert "BONSAI-RUN-" in (root / "BonsaiLab" / "CertificationRunRecorder.swift").read_text()

# Build 53 and CI packaging.
assert re.search(r'CURRENT_PROJECT_VERSION:\s*"53"', project)
assert "RC1.23.6 awaited listener rebind contracts" in workflow
assert "tools/rc1236_awaited_listener_rebind_contract_tests.py" in workflow
assert 'CFBundleVersion raw -o - "$APP/Info.plist")" = "53"' in workflow
assert "Build53-Awaited-Listener-Rebind-Candidate" in workflow

print("RC1.23.6 Build 53 awaited listener rebind contracts: PASS")
