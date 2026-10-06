from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
runtime = (ROOT / "BonsaiLab/RuntimeOptimization.swift").read_text(encoding="utf-8")
server = (ROOT / "BonsaiLab/LocalOpenAIServer.swift").read_text(encoding="utf-8")
view = (ROOT / "BonsaiLab/ProductionView.swift").read_text(encoding="utf-8")
runner = (ROOT / "tools/rc126_phase2f_prefill_batch_arm.ps1").read_text(encoding="utf-8")
project = (ROOT / "project.yml").read_text(encoding="utf-8")
workflow = (ROOT / ".github/workflows/build-ios.yml").read_text(encoding="utf-8")

for marker in [
    "enum Phase2FPrefillBatchArm",
    'case baseline32 = "BASELINE32"',
    'case candidate64 = "CANDIDATE64"',
    "Phase2FPrefillBatchLaunchLatch",
    "runtime.batch = value",
    "runtime.ubatch = value",
    "runtime.disableMetalTensorAPI = true",
]:
    assert marker in runtime, marker

for marker in [
    "Phase2FPrefillBatchLaunchLatch.apply(",
    "RC1.26 Build 74 Prefill Batch 32→64",
]:
    assert marker in view, marker

for marker in [
    'request.path == "/debug/phase2f/launch"',
    'request.path == "/debug/phase2f/next-launch"',
    '"RC1.26_PHASE2F_PREFILL_BATCH_32_VS_64_VIABILITY"',
    '"rc126.phase2f.prefill-batch-32-vs-64.v1"',
    '"active_batch": advertisedBatch',
    '"active_ubatch": advertisedUBatch',
    '"shape_evidence_valid":',
    '"rc1.26-build74-prefill-batch-32-vs-64"',
]:
    assert marker in server, marker

for marker in [
    'ValidateSet("BASELINE32", "CANDIDATE64")',
    '"/debug/phase2f/launch"',
    '"/debug/phase2f/next-launch"',
    "1..2",
    "avg_prefill_ms",
    "avg_ttft_ms",
    "Compress-Archive",
]:
    assert marker in runner, marker

assert 'CURRENT_PROJECT_VERSION: "74"' in project
assert "RC1.26 Phase 2F prefill batch contracts" in workflow
assert "tools/rc126_phase2f_prefill_batch_arm.ps1" in workflow

print("RC1.26 Phase 2F prefill batch 32 vs 64 contracts: PASS")
