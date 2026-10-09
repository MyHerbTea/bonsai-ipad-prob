from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

runtime = (ROOT / "BonsaiLab/RuntimeOptimization.swift").read_text(encoding="utf-8")
engine = (ROOT / "BonsaiLab/BonsaiEngine.swift").read_text(encoding="utf-8")
server = (ROOT / "BonsaiLab/LocalOpenAIServer.swift").read_text(encoding="utf-8")
view = (ROOT / "BonsaiLab/ProductionView.swift").read_text(encoding="utf-8")
bridge_h = (ROOT / "BonsaiLab/SystemProbeBridge.h").read_text(encoding="utf-8")
bridge_mm = (ROOT / "BonsaiLab/SystemProbeBridge.mm").read_text(encoding="utf-8")
runner = (ROOT / "tools/rc126_phase2c1_fresh_backend_arm.ps1").read_text(encoding="utf-8")
project = (ROOT / "project.yml").read_text(encoding="utf-8")
workflow = (ROOT / ".github/workflows/build-ios.yml").read_text(encoding="utf-8")

for marker in [
    "enum Phase2CMetalTensorLaunchArm",
    'case baseline = "BASELINE"',
    'case candidate = "CANDIDATE"',
    "static let processLaunchID = UUID().uuidString",
    "static let arm: Phase2CMetalTensorLaunchArm",
    "static func scheduleNext",
    "static func apply(to runtime: inout RuntimeConfig)",
    "runtime.disableMetalTensorAPI = arm != .candidate",
]:
    assert marker in runtime, marker

for marker in [
    "backendRegistryMetalTensorDisabledAtFirstInit",
    "PHASE2C1_METAL_TENSOR_RESTART_REQUIRED",
    "initializeBackendIfNeeded(",
    "BonsaiBeginMetalTensorBackendLogCapture()",
    "BonsaiEndMetalTensorBackendLogCapture()",
    "Phase2CMetalTensorLaunchLatch.backendArmKey",
    ".backendHasTensorKey",
]:
    assert marker in engine, marker

assert "backendRegistryMetalTensorDisabledAtFirstInit = nil" not in engine
assert 'setenv("GGML_METAL_TENSOR_DISABLE", "1", 1)' in engine
assert 'unsetenv("GGML_METAL_TENSOR_DISABLE")' in engine

for marker in [
    "BonsaiMetalTensorBackendLogEvidence",
    "BonsaiBeginMetalTensorBackendLogCapture",
    "BonsaiEndMetalTensorBackendLogCapture",
]:
    assert marker in bridge_h, marker

for marker in [
    "#include <llama/llama.h>",
    "llama_log_get(",
    "llama_log_set(",
    'std::strstr(text, "has tensor")',
    'std::strstr(text, "= true")',
    'std::strstr(text, "= false")',
]:
    assert marker in bridge_mm, marker

for marker in [
    'request.path == "/debug/phase2c/launch"',
    'request.path == "/debug/phase2c/next-launch"',
    '"RC1.26_PHASE2C1_FRESH_BACKEND_VIABILITY"',
    '"rc126.phase2c1.fresh-backend-launch-latch.v1"',
    '"requires_process_restart_between_arms": true',
    '"evidence_source":',
    '"pinned_prism_backend_init_log_has_tensor"',
    '"metal_tensor_prefill_dispatch_proven":',
    'false',
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
    or '"rc1.26-build90-certification-p1"' in server
    or '"rc1.26-build92-native-prefill-observability-p0"' in server
)

assert "Phase2CMetalTensorLaunchLatch.apply(" in view
assert (
    "RC1.26 Build 71 Fresh Backend Metal Tensor A/B" in view
    or "RC1.26 Build 72 Prefill Batch 8→16" in view
    or "RC1.26 Build 73 Prefill Batch 16→32" in view
    or "RC1.26 Build 75 API Cold-Start Guard" in view
    or "RC1.26 Build 76 M5 Extreme Text KV Lab" in view
    or "RC1.26 Build 77 M5 Extended Context Lab" in view
    or "RC1.26 Build 78 M5 Context Boundary Lab" in view
    or "RC1.26 Build 79 Storage-Memory Long Context Lab" in view
    or "RC1.26 Build 80 Long-Context Tier Reload Fix" in view
    or "RC1.26 Build 81 32K Memory Squeeze" in view
    or "RC1.26 Build 82 Unified-Metal 32K Lab" in view
    or "RC1.26 Build 89 Compact Scheduler Metadata" in view
    or "RC1.26 Build 92 Native Prefill Observability P0" in view
)

for marker in [
    'ValidateSet("BASELINE", "CANDIDATE")',
    '"/debug/phase2c/launch"',
    '"/debug/phase2c/next-launch"',
    "backend_evidence_valid",
    "warmup",
    "measure_$_",
    "avg_prefill_ms",
    "avg_ttft_ms",
    "avg_tokens_per_second",
    "Compress-Archive",
]:
    assert marker in runner, marker

assert (
    'CURRENT_PROJECT_VERSION: "71"' in project
    or 'CURRENT_PROJECT_VERSION: "72"' in project
    or 'CURRENT_PROJECT_VERSION: "73"' in project
    or 'CURRENT_PROJECT_VERSION: "75"' in project
    or 'CURRENT_PROJECT_VERSION: "76"' in project
    or 'CURRENT_PROJECT_VERSION: "77"' in project
    or 'CURRENT_PROJECT_VERSION: "78"' in project
    or 'CURRENT_PROJECT_VERSION: "79"' in project
    or 'CURRENT_PROJECT_VERSION: "80"' in project
    or 'CURRENT_PROJECT_VERSION: "81"' in project
    or 'CURRENT_PROJECT_VERSION: "82"' in project
    or 'CURRENT_PROJECT_VERSION: "90"' in project
    or 'CURRENT_PROJECT_VERSION: "92"' in project
)
assert "RC1.26 Phase 2C-1 fresh backend contracts" in workflow
assert "tools/rc126_phase2c1_fresh_backend_contract_tests.py" in workflow

# The experiment must require an external process restart; it must not kill
# or relaunch the app programmatically.
assert "exit(0)" not in engine + "\n" + server + "\n" + view
assert "UIApplication.shared" not in runner

print("RC1.26 Phase 2C-1 fresh-backend launch-latch contracts: PASS")
