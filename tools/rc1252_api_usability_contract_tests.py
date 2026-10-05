from pathlib import Path

root = Path(__file__).resolve().parents[1]
server = (root / "BonsaiLab" / "LocalOpenAIServer.swift").read_text(encoding="utf-8")
view = (root / "BonsaiLab" / "ProductionView.swift").read_text(encoding="utf-8")
project = (root / "project.yml").read_text(encoding="utf-8")
workflow = (root / ".github" / "workflows" / "build-ios.yml").read_text(encoding="utf-8")

# Build identity
assert 'CURRENT_PROJECT_VERSION: "61"' in project
assert "RC1.25.2 Build 61 API Context Ladder" in view

# Context ladder: frozen 512 default plus explicit device-validation candidates.
for value in ["512", "768", "1024", "2048"]:
    assert f'Text("{value}").tag("{value}")' in view
assert '.disabled(apiServer.isRunning)' in view
assert 'Int(apiContextProfile) ?? 512' in view
assert 'apiRuntime.context = selectedAPIContext' in view

# Discovery metadata must expose fields consumed by OpenAI-compatible clients.
for marker in [
    '"context_length": contextWindow',
    '"max_output_tokens": maxOutputTokens',
    '"input_modalities": ["text", "image"]',
    '"output_modalities": ["text"]',
    '"tools": false',
    '"reasoning": false',
    '"responses_api": false',
    '"max_images_per_request": 3',
]:
    assert marker in server

# Do not falsely advertise unsupported tool/reasoning parameters.
model_block = server[server.index('private static func modelObject'):]
assert '"tool_choice"' not in model_block.split('private static func errorObject', 1)[0]
assert '"tools"' not in model_block.split('"supported_parameters": [', 1)[1].split(']', 1)[0]
assert '"reasoning_effort"' not in model_block.split('"supported_parameters": [', 1)[1].split(']', 1)[0]

# The active runtime config is also what discovery publishes.
assert "apiServer.configureModelMetadata(" in view
assert "contextWindow: selectedAPIContext" in view
assert "maxOutputTokens: 256" in view

# Build 60 invariants remain.
assert 'request.path == "/v1/chat/completions"' in server
assert 'request.path == "/v1/models"' in server
assert "unsupportedTools" in server
assert "context_length_exceeded" in view

# CI must execute this contract and package Build 61.
assert "python3 tools/rc1252_api_usability_contract_tests.py" in workflow
assert 'CFBundleVersion raw -o - "$APP/Info.plist")" = "61"' in workflow

print("RC1.25.2 Build 61 API usability contracts: PASS")
