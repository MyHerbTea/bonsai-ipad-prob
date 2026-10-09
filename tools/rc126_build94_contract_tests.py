#!/usr/bin/env python3
"""Build94 source contract; actual app build and Swift policy tests run in macOS CI."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
view = (root / "BonsaiLab/ProductionView.swift").read_text()
server = (root / "BonsaiLab/LocalOpenAIServer.swift").read_text()
engine = (root / "BonsaiLab/BonsaiEngine.swift").read_text()
policy = (root / "BonsaiLab/Build94BatchExperiment.swift").read_text()
workflow = (root / ".github/workflows/build-ios.yml").read_text()
project = (root / "project.yml").read_text()
assert ('CURRENT_PROJECT_VERSION: "94"' in project or 'CURRENT_PROJECT_VERSION: "95"' in project)
assert ('RC126APIStartupLifecycle.begin(build: "94")' in view or 'RC126APIStartupLifecycle.begin(build: "95")' in view)
assert ('"build_id": "rc1.26-build94-prefill-kernel-boundary-p0"' in server or '"build_id": "rc1.26-build95-native-k1-ptq1-dense5"' in server)
assert '"schema": "bonsai-build94-execution-v1"' in server
assert "Build94BatchExperiment.select(context: context)" in view
assert "case .candidate16: batchCap = 16" in view
assert "case .baseline8: batchCap = 8" in view
assert "default: batchCap = 4" in view
assert "Build94BatchExperiment.noteTextSuccess(" in view
assert "Build94BatchExperiment.noteStartupFailure()" in view
assert "Build94BatchExperiment.scheduleNext(" in server
assert "/debug/build94/next-launch" in server
assert "/debug/build94/launch" in server
assert "native_completed_batches" in server
assert "native_decode_wall_ms_total" in server
assert "native_average_batch_ms" in server
assert 'if stage == "decode_begin"' in server
assert 'else if stage == "decode_end"' in server
assert server.index('entry["native_batch_last_completed_ms"] = max(0, durationMs)') > server.index('else if stage == "decode_end"')
assert 'contextParams.n_batch = UInt32(config.batch)' in engine
assert 'contextParams.n_ubatch = UInt32(config.ubatch)' in engine
assert "adfffbe41b2cabcd51fff326ab045662265062bb" in workflow
assert "rc126_build94_policy_tests.swift" in workflow
assert ('build94-prefill-kernel-boundary-p0-unsigned.ipa' in workflow or 'build95-native-k1-ptq1-dense5-unsigned.ipa' in workflow)
assert ('Build94-Prefill-Kernel-Boundary-P0' in workflow or 'Build95-Native-K1-PTQ1-Dense5' in workflow)
for marker in ["pendingKey", "fallbackKey", "baselineOKKey", "confirmedKey", "scheduleNext", "noteStartupFailure", "noteTextSuccess"]:
    assert marker in policy, marker
print("Build94 guarded 32K batch8/16, safe4 recovery, observer-only timing: PASS")
