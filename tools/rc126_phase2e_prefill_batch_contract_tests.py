from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

runtime = (ROOT / "BonsaiLab/RuntimeOptimization.swift").read_text(encoding="utf-8")
server = (ROOT / "BonsaiLab/LocalOpenAIServer.swift").read_text(encoding="utf-8")
view = (ROOT / "BonsaiLab/ProductionView.swift").read_text(encoding="utf-8")
runner = (ROOT / "tools/rc126_phase2e_prefill_batch_arm.ps1").read_text(encoding="utf-8")
project = (ROOT / "project.yml").read_text(encoding="utf-8")
workflow = (ROOT / ".github/workflows/build-ios.yml").read_text(encoding="utf-8")

for marker in [
    "enum Phase2EPrefillBatchArm",
    'case baseline16 = "BASELINE16"',
    'case candidate32 = "CANDIDATE32"',
    "Phase2EPrefillBatchLaunchLatch",
    "runtime.batch = value",
    "runtime.ubatch = value",
    "runtime.disableMetalTensorAPI = true",
]:
    assert marker in runtime, marker

for marker in [
    "Phase2EPrefillBatchLaunchLatch.apply(",
    "RC1.26 Build 73 Prefill Batch 16→32",
]:
    assert marker in view, marker

for marker in [
    'request.path == "/debug/phase2e/launch"',
    'request.path == "/debug/phase2e/next-launch"',
    '"RC1.26_PHASE2E_PREFILL_BATCH_16_VS_32_VIABILITY"',
    '"rc126.phase2e.prefill-batch-16-vs-32.v1"',
    '"active_batch": advertisedBatch',
    '"active_ubatch": advertisedUBatch',
    '"shape_evidence_valid":',
    '"rc1.26-build73-prefill-batch-16-vs-32"',
]:
    assert marker in server, marker

for marker in [
    'ValidateSet("BASELINE16", "CANDIDATE32")',
    '"/debug/phase2e/launch"',
    '"/debug/phase2e/next-launch"',
    "1..2",
    "avg_prefill_ms",
    "avg_ttft_ms",
    "Compress-Archive",
]:
    assert marker in runner, marker

assert 'CURRENT_PROJECT_VERSION: "73"' in project
assert "RC1.26 Phase 2E prefill batch contracts" in workflow
assert "tools/rc126_phase2e_prefill_batch_arm.ps1" in workflow

print("RC1.26 Phase 2E prefill batch 16 vs 32 contracts: PASS")
