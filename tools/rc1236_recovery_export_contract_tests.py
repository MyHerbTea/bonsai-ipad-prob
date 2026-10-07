from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
recorder = (root / "BonsaiLab" / "CertificationRunRecorder.swift").read_text()
view = (root / "BonsaiLab" / "ProductionView.swift").read_text()
project = (root / "project.yml").read_text()
workflow = (root / ".github" / "workflows" / "build-ios.yml").read_text()

# Recorder must be able to rediscover completed archives from disk instead of
# relying only on an in-memory latestArchiveURL.
assert "func refreshLatestArchiveFromDisk()" in recorder
assert "BonsaiCertificationRuns" in recorder
assert "contentsOfDirectory" in recorder
assert "contentModificationDateKey" in recorder
assert "latestArchiveURL" in recorder

# Recovery must refresh disk-backed export state on every outcome.
recover_start = recorder.index("func recoverInterruptedRunIfNeeded()")
recover_end = recorder.index("private func persistedDiagnosticFile", recover_start)
recover = recorder[recover_start:recover_end]
assert recover.count("refreshLatestArchiveFromDisk") >= 2

# UI must always expose a recovery/export section and call refresh on appear.
assert 'Section("RC1.23.6 Restart Certification")' in view
assert "refreshLatestArchiveFromDisk()" in view
assert 'Label("分享最近测试结果"' in view
assert 'Text("暂无可分享的测试存档")' in view

# Existing one-click runner remains present.
assert 'Button("运行 Restart Certification")' in view
assert "runRestartCertification()" in view
assert "let certificationCycles = 4" in view

# 512 remains the default/restart baseline; RC1.25.2 may expose larger
# product API contexts without restoring the rejected 256 option.
assert ('private var apiContextProfile = "512"' in view or 'private var apiContextProfile = "4096"' in view)
assert 'Text("256 Experimental")' not in view
if "RC1.25.2" in view:
    assert ('Int(apiContextProfile) ?? 512' in view or 'Int(apiContextProfile) ?? 4096' in view)
    for value in ["512", "768", "1024", "2048"]:
        assert f'.tag("{value}")' in view
else:
    assert re.search(r'let\s+selectedAPIContext\s*=\s*512', view)

# Build 51+ retains recovery/export behavior.
build_match = re.search(
    r'CURRENT_PROJECT_VERSION:\s*"(?P<build>\d+)"',
    project,
)
assert build_match is not None
assert int(build_match.group("build")) >= 51
assert "RC1.23.6 recovery export contracts" in workflow
assert "tools/rc1236_recovery_export_contract_tests.py" in workflow

print("RC1.23.6 Build 51 recovery export contracts: PASS")
