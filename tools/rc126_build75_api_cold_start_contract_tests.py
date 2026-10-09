from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

view = (ROOT / "BonsaiLab/ProductionView.swift").read_text(encoding="utf-8")
engine = (ROOT / "BonsaiLab/BonsaiEngine.swift").read_text(encoding="utf-8")
server = (ROOT / "BonsaiLab/LocalOpenAIServer.swift").read_text(encoding="utf-8")
project = (ROOT / "project.yml").read_text(encoding="utf-8")
workflow = (ROOT / ".github/workflows/build-ios.yml").read_text(encoding="utf-8")
probe = (ROOT / "tools/rc126_build75_api_cold_start_probe.ps1").read_text(encoding="utf-8")

for marker in [
    "private enum RC126APIStartupLifecycle",
    '"BonsaiRC126APIStartupStage"',
    '"BonsaiRC126APIPreviousIncompleteStage"',
    '"BonsaiRC126APIStartupAttempt"',
    'RC126APIStartupLifecycle.mark("VISION_RELEASE_BEGIN")',
    'releaseResidentStateForContextSwitch()',
    '"BACKEND_PREWARM_BEGIN"',
    'prepareAPIColdStart(',
    'Task.sleep(',
    '"MODEL_LOAD_BEGIN"',
    '"MODEL_READY"',
    '"LISTENER_BIND_REQUESTED"',
    'waitForCertificationAPIReady(',
    'RC126APIStartupLifecycle.ready()',
    'RC126APIStartupLifecycle.fail(error)',
    'apiServer.runtimeBatch',
    'apiServer.runtimeUBatch',
]:
    assert marker in view, marker

assert (
    'RC126APIStartupLifecycle.begin(build: "75")' in view
    or 'RC126APIStartupLifecycle.begin(build: "76")' in view
    or 'RC126APIStartupLifecycle.begin(build: "77")' in view
    or 'RC126APIStartupLifecycle.begin(build: "78")' in view
    or 'RC126APIStartupLifecycle.begin(build: "79")' in view
    or 'RC126APIStartupLifecycle.begin(build: "80")' in view
    or 'RC126APIStartupLifecycle.begin(build: "81")' in view
    or 'RC126APIStartupLifecycle.begin(build: "82")' in view
    or 'RC126APIStartupLifecycle.begin(build: "94")' in view
    or 'RC126APIStartupLifecycle.begin(build: "96")' in view
)
assert (
    'RC1.26 Build 75 API Cold-Start Guard' in view
    or 'RC1.26 Build 76 M5 Extreme Text KV Lab' in view
    or 'RC1.26 Build 77 M5 Extended Context Lab' in view
    or 'RC1.26 Build 78 M5 Context Boundary Lab' in view
    or 'RC1.26 Build 79 Storage-Memory Long Context Lab' in view
    or 'RC1.26 Build 80 Long-Context Tier Reload Fix' in view
    or 'RC1.26 Build 81 32K Memory Squeeze' in view
    or 'RC1.26 Build 82 Unified-Metal 32K Lab' in view
    or 'RC1.26 Build 89 Compact Scheduler Metadata' in view
    or 'RC1.26 Build 92 Native Prefill Observability P0' in view
)
assert (
    '"rc1.26-build75-api-cold-start-guard"' in server
    or '"rc1.26-build76-text-kv-reuse-lab"' in server
    or '"rc1.26-build77-extended-context-lab"' in server
    or '"rc1.26-build78-context-boundary-lab"' in server
    or '"rc1.26-build79-storage-memory-long-context-lab"' in server
    or '"rc1.26-build80-long-context-tier-reload-fix"' in server
    or '"rc1.26-build81-32k-memory-squeeze"' in server
    or '"rc1.26-build82-unified-metal-32k-lab"' in server
    or '"rc1.26-build94-prefill-kernel-boundary-p0"' in server
    or '"rc1.26-build96-native-k2-gdn-simd"' in server
)

for marker in [
    "func prepareAPIColdStart(",
    '"API_COLD_00_BEGIN"',
    '"API_COLD_01_RUNTIME_RELEASED"',
    '"API_COLD_02_BACKEND_INIT_BEGIN"',
    '"API_COLD_03_BACKEND_INIT_DONE"',
    '"API_COLD_04_BACKEND_READY"',
    'persistSystemDiagnostics(',
]:
    assert marker in engine, marker

for marker in [
    "var runtimeBatch: Int",
    "var runtimeUBatch: Int",
    '"api_startup_stage"',
    '"api_startup_previous_incomplete"',
    '"api_startup_attempt"',
    '"api_startup_last_error"',
]:
    assert marker in server, marker

for marker in [
    '"/health"',
    '"/debug/build"',
    '"/debug/phase2f/launch"',
    "startup_stage =",
    "startup_previous_incomplete =",
    "Compress-Archive",
]:
    assert marker in probe, marker

assert (
    'CURRENT_PROJECT_VERSION: "75"' in project
    or 'CURRENT_PROJECT_VERSION: "76"' in project
    or 'CURRENT_PROJECT_VERSION: "77"' in project
    or 'CURRENT_PROJECT_VERSION: "78"' in project
    or 'CURRENT_PROJECT_VERSION: "79"' in project
    or 'CURRENT_PROJECT_VERSION: "80"' in project
    or 'CURRENT_PROJECT_VERSION: "81"' in project
    or 'CURRENT_PROJECT_VERSION: "82"' in project
    or 'CURRENT_PROJECT_VERSION: "94"' in project
    or 'CURRENT_PROJECT_VERSION: "96"' in project
)
assert "RC1.26 Build 75 cold-start guard contracts" in workflow
assert "tools/rc126_build75_api_cold_start_probe.ps1" in workflow

print("RC1.26 Build 75 API cold-start guard contracts: PASS")
