from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

runtime = (ROOT / "BonsaiLab/RuntimeOptimization.swift").read_text(encoding="utf-8")
server = (ROOT / "BonsaiLab/LocalOpenAIServer.swift").read_text(encoding="utf-8")
view = (ROOT / "BonsaiLab/ProductionView.swift").read_text(encoding="utf-8")
runner = (ROOT / "tools/rc126_phase2d_prefill_batch_arm.ps1").read_text(encoding="utf-8")
project = (ROOT / "project.yml").read_text(encoding="utf-8")
workflow = (ROOT / ".github/workflows/build-ios.yml").read_text(encoding="utf-8")

for marker in [
    "enum Phase2DPrefillBatchArm",
    'case baseline8 = "BASELINE8"',
    'case candidate16 = "CANDIDATE16"',
    "static let processLaunchID = UUID().uuidString",
    "runtime.batch = value",
    "runtime.ubatch = value",
    "runtime.disableMetalTensorAPI = true",
]:
    assert marker in runtime, marker

for marker in [
    "Phase2DPrefillBatchLaunchLatch.apply(",
    "configureRuntimeShape(",
]:
    assert marker in view, marker
assert (
    "RC1.26 Build 72 Prefill Batch 8→16" in view
    or "RC1.26 Build 73 Prefill Batch 16→32" in view
    or "RC1.26 Build 75 API Cold-Start Guard" in view
    or "RC1.26 Build 76 M5 Extreme Text KV Lab" in view
    or "RC1.26 Build 77 M5 Extended Context Lab" in view
    or "RC1.26 Build 78 M5 Context Boundary Lab" in view
    or "RC1.26 Build 79 Storage-Memory Long Context Lab" in view
)

for marker in [
    'request.path == "/debug/phase2d/launch"',
    'request.path == "/debug/phase2d/next-launch"',
    '"RC1.26_PHASE2D_PREFILL_BATCH_SHAPE_VIABILITY"',
    '"rc126.phase2d.prefill-batch-8-vs-16.v1"',
    '"active_batch": advertisedBatch',
    '"active_ubatch": advertisedUBatch',
    '"shape_evidence_valid":',
    '"metal_tensor_forced_baseline": true',
]:
    assert marker in server, marker

assert (
    '"rc1.26-build75-api-cold-start-guard"' in server
    or '"rc1.26-build76-text-kv-reuse-lab"' in server
    or '"rc1.26-build77-extended-context-lab"' in server
    or '"rc1.26-build78-context-boundary-lab"' in server
    or '"rc1.26-build79-storage-memory-long-context-lab"' in server
)

for marker in [
    'ValidateSet("BASELINE8", "CANDIDATE16")',
    '"/debug/phase2d/launch"',
    '"/debug/phase2d/next-launch"',
    "1..2",
    "prompt_tokens",
    "avg_prefill_ms",
    "avg_ttft_ms",
    "Compress-Archive",
]:
    assert marker in runner, marker

assert (
    'CURRENT_PROJECT_VERSION: "72"' in project
    or 'CURRENT_PROJECT_VERSION: "73"' in project
    or 'CURRENT_PROJECT_VERSION: "75"' in project
    or 'CURRENT_PROJECT_VERSION: "76"' in project
    or 'CURRENT_PROJECT_VERSION: "77"' in project
    or 'CURRENT_PROJECT_VERSION: "78"' in project
    or 'CURRENT_PROJECT_VERSION: "79"' in project
)
assert "RC1.26 Phase 2D prefill batch contracts" in workflow
assert "tools/rc126_phase2d_prefill_batch_arm.ps1" in workflow

print("RC1.26 Phase 2D prefill batch 8 vs 16 contracts: PASS")
