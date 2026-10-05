from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
view = (root / "BonsaiLab" / "ProductionView.swift").read_text()
engine = (root / "BonsaiLab" / "BonsaiEngine.swift").read_text()
types = (root / "BonsaiLab" / "LabTypes.swift").read_text()
server = (root / "BonsaiLab" / "LocalOpenAIServer.swift").read_text()
project = (root / "project.yml").read_text()
workflow = (root / ".github" / "workflows" / "build-ios.yml").read_text()

# RC1.25.1 behavior remains inherited even when a later release changes UI identity.

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

# Production runtime invariants remain inherited. Later releases may add
# explicit context profiles, but 512 must remain the default/frozen baseline.
assert 'private var apiRuntimeProfile = "accelerated"' in view
assert 'private var apiContextProfile = "512"' in view
assert re.search(r'apiRuntime\.batch\s*=\s*8', view)
assert re.search(r'apiRuntime\.ubatch\s*=\s*8', view)
assert 'apiRuntime.kvUnified = true' in view
assert 'apiRuntime.loadMode = .mmap' in view

match = re.search(r'CURRENT_PROJECT_VERSION:\s*"([0-9]+)"', project)
assert match is not None
assert int(match.group(1)) >= 60

assert "RC1.25.1 API hardening contracts" in workflow
assert "tools/rc1251_api_hardening_contract_tests.py" in workflow

print("RC1.25.1 inherited API hardening contracts: PASS")
