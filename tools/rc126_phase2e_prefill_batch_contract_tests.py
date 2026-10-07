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
]:
    assert marker in view, marker
assert (
    "RC1.26 Build 73 Prefill Batch 16→32" in view
    or "RC1.26 Build 75 API Cold-Start Guard" in view
    or "RC1.26 Build 76 M5 Extreme Text KV Lab" in view
    or "RC1.26 Build 77 M5 Extended Context Lab" in view
    or "RC1.26 Build 78 M5 Context Boundary Lab" in view
    or "RC1.26 Build 79 Storage-Memory Long Context Lab" in view
    or "RC1.26 Build 80 Long-Context Tier Reload Fix" in view
    or "RC1.26 Build 81 32K Memory Squeeze" in view
    or "RC1.26 Build 82 Unified-Metal 32K Lab" in view
)

for marker in [
    'request.path == "/debug/phase2e/launch"',
    'request.path == "/debug/phase2e/next-launch"',
    '"RC1.26_PHASE2E_PREFILL_BATCH_16_VS_32_VIABILITY"',
    '"rc126.phase2e.prefill-batch-16-vs-32.v1"',
    '"active_batch": advertisedBatch',
    '"active_ubatch": advertisedUBatch',
    '"shape_evidence_valid":',
]:
    assert marker in server, marker

assert (
    '"rc1.26-build75-api-cold-start-guard"' in server
    or '"rc1.26-build76-text-kv-reuse-lab"' in server
    or '"rc1.26-build77-extended-context-lab"' in server
    or '"rc1.26-build78-context-boundary-lab"' in server
    or '"rc1.26-build79-storage-memory-long-context-lab"' in server
    or '"rc1.26-build80-long-context-tier-reload-fix"' in server
    or '"rc1.26-build81-32k-memory-squeeze"' in server
    or '"rc1.26-build82-unified-metal-32k-lab"' in server
)

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

assert (
    'CURRENT_PROJECT_VERSION: "73"' in project
    or 'CURRENT_PROJECT_VERSION: "75"' in project
    or 'CURRENT_PROJECT_VERSION: "76"' in project
    or 'CURRENT_PROJECT_VERSION: "77"' in project
    or 'CURRENT_PROJECT_VERSION: "78"' in project
    or 'CURRENT_PROJECT_VERSION: "79"' in project
    or 'CURRENT_PROJECT_VERSION: "80"' in project
    or 'CURRENT_PROJECT_VERSION: "81"' in project
    or 'CURRENT_PROJECT_VERSION: "82"' in project
)
assert "RC1.26 Phase 2E prefill batch contracts" in workflow
assert "tools/rc126_phase2e_prefill_batch_arm.ps1" in workflow

print("RC1.26 Phase 2E prefill batch 16 vs 32 contracts: PASS")
