from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
server = (root / "BonsaiLab" / "LocalOpenAIServer.swift").read_text()
view = (root / "BonsaiLab" / "ProductionView.swift").read_text()
project = (root / "project.yml").read_text()
workflow = (root / ".github" / "workflows" / "build-ios.yml").read_text()

# Product lifecycle surface: listener stop/resume is separate from runtime release.
assert "var canResumePreservedRuntime: Bool" in server
assert "func stopListenerPreservingHandler() async" in server
pause_start = server.index("func stopListenerPreservingHandler() async")
pause_end = server.index(
    "func restartListenerPreservingHandler(",
    pause_start,
)
pause = server[pause_start:pause_end]
assert "await cancelListenerForRestart()" in pause
assert re.search(
    r'handler\s*!=\s*nil',
    server,
)

# Product UI buttons must route through the shared product helpers.
assert "private func pauseAPIServerPreservingRuntime()" in view
assert "private func startOrResumeAPIServer()" in view
assert 'Button("停止 API")' in view
assert "pauseAPIServerPreservingRuntime()" in view
assert 'apiServer.canResumePreservedRuntime' in view
assert 'startOrResumeAPIServer()' in view
assert '"恢复 OpenAI API"' in view

# Stopping the normal API must not directly unload the 27B runtime.
stop_button = view[
    view.index('Button("停止 API")'):
    view.index('Button("复制 API 配置")')
]
assert "engine.unloadAll()" not in stop_button
assert "apiServer.stop()" not in stop_button

# Explicit full lifecycle boundaries still clear handler + release engine.
assert re.search(
    r'newPhase\s*==\s*\.background[\s\S]{0,500}'
    r'apiServer\.stop\(\)[\s\S]{0,500}'
    r'engine\.unloadAll\(\)',
    view,
)
handle_start = view.index("private func handleImport(")
handle_end = view.index("private func runMLXVisionProbe()", handle_start)
handle = view[handle_start:handle_end]
assert handle.count("apiServer.stop()") >= 3
assert "await engine.unloadAll()" in handle

# Build 54 certification must exercise product stop + product resume helpers,
# not call the low-level listener restart directly in cycles 2+.
runner_start = view.index("private func runRestartCertification()")
runner_end = view.index(
    "private func waitForCertificationAPIReady",
    runner_start,
)
runner = view[runner_start:runner_end]
assert '"product_stop_requested"' in runner
assert '"product_stop_completed"' in runner
assert '"product_resume_requested"' in runner
assert '"product_resume_ready"' in runner
assert "pauseAPIListenerPreservingRuntime()" in runner
assert "resumeAPIListenerPreservingRuntime()" in runner
resident_branch_start = runner.index("} else {", runner.index("if cycle == 1"))
resident_branch_end = runner.index(
    "try await waitForCertificationAPIReady",
    resident_branch_start,
)
resident_branch = runner[resident_branch_start:resident_branch_end]
assert "engine.unloadAll()" not in resident_branch
assert "startAPIServer()" not in resident_branch

# Frozen default/restart-runner inference behavior remains untouched. Later
# product releases may expose larger explicit contexts, but the certification
# runner continues to force the certified 512/accelerated baseline.
assert 'private var apiContextProfile = "512"' in view
assert 'Text("256 Experimental")' not in view
assert 'apiContextProfile = "512"' in runner
assert 'apiRuntimeProfile = "accelerated"' in runner
assert "visionPrefixKVReuseEnabled = true" in runner

# Single-file device evidence remains the only user handoff.
assert "certificationRecorder.finishRun(" in view
assert 'Label("分享最近测试结果"' in view
assert "BONSAI-RUN-" in (
    root / "BonsaiLab" / "CertificationRunRecorder.swift"
).read_text()

# Build 54+ descendants must continue to preserve the product lifecycle
# contract. Exact Build 54 packaging identity is frozen on the dedicated
# frozen branch; later diagnostic builds may carry a higher bundle build.
build_match = re.search(
    r'CURRENT_PROJECT_VERSION:\s*"(?P<build>\d+)"',
    project,
)
assert build_match is not None
assert int(build_match.group("build")) >= 54
assert "RC1.23.6 production stop resume contracts" in workflow
assert "tools/rc1236_production_stop_resume_contract_tests.py" in workflow
assert "pauseAPIServerPreservingRuntime()" in view
assert "startOrResumeAPIServer()" in view

print("RC1.23.6 Build 54+ production stop/resume contracts: PASS")
