from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
view = (root / "BonsaiLab" / "ProductionView.swift").read_text()
engine = (root / "BonsaiLab" / "BonsaiEngine.swift").read_text()
types = (root / "BonsaiLab" / "LabTypes.swift").read_text()
server = (root / "BonsaiLab" / "LocalOpenAIServer.swift").read_text()
project = (root / "project.yml").read_text()
workflow = (root / ".github" / "workflows" / "build-ios.yml").read_text()

# RC1.25.1 semantics must survive in descendants.
assert (
    'Text("1.0 · RC1.25.1 API Hardening")' in view
    or 'Text("1.0 · RC1.25.2 Build 63 Vision Lifecycle Safety")' in view
    or 'Text("1.0 · RC1.25.3 Build 64 Native Prefill Isolation")' in view
    or 'Text("1.0 · RC1.26 Build 65 Runtime Optimization Lab")' in view

    or 'Text("1.0 · RC1.26 Build 66 Memory Governor Observer")' in view


    or 'Text("1.0 · RC1.26 Build 67 Request Lifecycle Governor Observer")' in view



    or 'Text("1.0 · RC1.26 Build 68 Heap Pressure Relief")' in view
    or 'Text("1.0 · RC1.26 Build 69 Metal Prefill Measurement")' in view
    or 'Text("1.0 · RC1.26 Build 70 Metal Prefill Measurement")' in view
    or 'Text("1.0 · RC1.26 Build 71 Fresh Backend Metal Tensor A/B")' in view
    or 'Text("1.0 · RC1.26 Build 72 Prefill Batch 8→16")' in view
    or 'Text("1.0 · RC1.26 Build 75 API Cold-Start Guard")' in view
    or 'Text("1.0 · RC1.26 Build 76 M5 Extreme Text KV Lab")' in view
    or 'Text("1.0 · RC1.26 Build 77 M5 Extended Context Lab")' in view
    or 'Text("1.0 · RC1.26 Build 78 M5 Context Boundary Lab")' in view
    or 'Text("1.0 · RC1.26 Build 79 Storage-Memory Long Context Lab")' in view
    or 'Text("1.0 · RC1.26 Build 80 Long-Context Tier Reload Fix")' in view
    or 'Text("1.0 · RC1.26 Build 81 32K Memory Squeeze")' in view
)
assert (
    'RC1.25.1 Build 60 Dual Context Admission' in view
    or 'RC1.25.2 Build 63 API Context Ladder' in view
    or 'RC1.25.3 Build 64 API Context Ladder' in view
    or 'RC1.26 Build 75 API 冷启动保护' in view
    or 'RC1.26 Build 76 M5 Extreme Text KV Lab' in view
    or 'RC1.26 Build 77 M5 Extended Context Lab' in view
    or 'RC1.26 Build 78 M5 Context Boundary Lab' in view
    or 'RC1.26 Build 79 Storage-Memory Long Context Lab' in view
    or 'RC1.26 Build 80 Long-Context Tier Reload Fix' in view
    or 'RC1.26 Build 81 32K Memory Squeeze' in view
)

# Multi-image success telemetry must preserve the already computed request route.
vision_start = view.index("static func persistVisionSuccess(")
text_start = view.index("static func persistTextSuccess(", vision_start)
vision_block = view[vision_start:text_start]
assert "route: String" in vision_block
assert '"route=\\(route)"' in vision_block
assert '"route=vision"' not in vision_block
assert "route: requestRoute" in view
assert 'requestRoute = "vision_multi"' in view

# Full-budget vision API errors must report real accounting components.
assert "case contextBudgetExceeded(" in types
for marker in [
    "input_positions=",
    "prompt_kv_tokens=",
    "requested_output_tokens=",
    "required_context=",
    "configured_context=",
    "maximum_safe_output=",
]:
    assert marker in types
assert "LabError.contextBudgetExceeded(" in engine
assert "requestedOutputTokens:" in engine
assert "contextLimit:" in engine
assert ".contextBudgetExceeded:" in view
assert '"context_length_exceeded"' in view

# Non-stream JSON responses explicitly declare UTF-8. SSE already did this.
assert 'contentType: "application/json; charset=utf-8"' in server
assert '"Content-Type: text/event-stream; charset=utf-8"' in server

# Production runtime mechanics remain frozen. RC1.25.2 explicitly evolves the
# selectable context only; Full/Accelerated and batch/uBatch remain unchanged.
assert 'private var apiRuntimeProfile = "accelerated"' in view
if "RC1.25.2" in view:
    assert ('Int(apiContextProfile) ?? 512' in view or 'Int(apiContextProfile) ?? 4096' in view)
    assert '"512", "768", "1024", "2048"' in view
else:
    assert re.search(r'let\s+selectedAPIContext\s*=\s*512', view)
assert re.search(r'apiRuntime\.batch\s*=\s*8', view)
assert re.search(r'apiRuntime\.ubatch\s*=\s*8', view)
assert 'apiRuntime.kvUnified = true' in view
assert 'apiRuntime.loadMode = .mmap' in view

match = re.search(r'CURRENT_PROJECT_VERSION:\s*"([0-9]+)"', project)
assert match is not None
assert int(match.group(1)) >= 60

assert "lab-v1-rc1-25-1-observability-error-hardening" in workflow
assert "RC1.25.1 API hardening contracts" in workflow
assert "tools/rc1251_api_hardening_contract_tests.py" in workflow
assert 'CFBundleVersion raw -o - "$APP/Info.plist")" = "' in workflow
assert (
    "Build60-Dual-Context-Admission" in workflow
    or "Build61-API-Usability" in workflow
    or "Build62-API-Usability" in workflow
    or "Build63-Vision-Lifecycle-Safety" in workflow
    or "Build64-Native-Prefill-Isolation" in workflow
    or "Build65-Runtime-Optimization" in workflow
    or "Build66-Memory-Governor-Observer" in workflow
    or "Build67-Request-Lifecycle-Governor-Observer" in workflow
    or "Build68-Heap-Pressure-Relief" in workflow
    or "Build69-Metal-Prefill-Measurement" in workflow
    or "Build70-Metal-Prefill-Measurement" in workflow
    or "Build71-Fresh-Backend-Metal-Tensor-AB" in workflow
    or "Build72-Prefill-Batch-8-vs-16" in workflow
    or "Build75-API-Cold-Start-Guard" in workflow
    or "Build76-M5-Extreme-Text-KV-Lab" in workflow
    or "Build77-M5-Extended-Context-Lab" in workflow
    or "Build78-M5-Context-Boundary-Lab" in workflow
    or "Build79-Storage-Memory-Long-Context-Lab" in workflow
    or "Build80-Long-Context-Tier-Reload-Fix" in workflow
    or "Build81-32K-Memory-Squeeze" in workflow
)

print("RC1.25.1 Build 60 API hardening contracts: PASS")
