from pathlib import Path

root = Path(__file__).resolve().parents[1]
server = (root / "BonsaiLab" / "LocalOpenAIServer.swift").read_text(encoding="utf-8")
view = (root / "BonsaiLab" / "ProductionView.swift").read_text(encoding="utf-8")
project = (root / "project.yml").read_text(encoding="utf-8")
workflow = (root / ".github" / "workflows" / "build-ios.yml").read_text(encoding="utf-8")
boundary_probe = (root / "tools" / "rc1252_context_boundary_probe.ps1").read_text(encoding="utf-8")
probe = (root / "tools" / "rc1252_context_ladder_device_probe.ps1").read_text(encoding="utf-8")
py_sdk_probe = (root / "tools" / "rc1252_openai_python_sdk_probe.py").read_text(encoding="utf-8")
js_sdk_probe = (root / "tools" / "rc1252_openai_js_sdk_probe.mjs").read_text(encoding="utf-8")

# Build identity
assert 'CURRENT_PROJECT_VERSION: "61"' in project
assert "RC1.25.2 Build 61 API Context Ladder" in view

# Context ladder: frozen 512 default plus explicit device-validation candidates.
for value in ["512", "768", "1024", "2048"]:
    assert f'Text("{value}").tag("{value}")' in view
assert '.disabled(apiServer.isRunning)' in view
assert 'Int(apiContextProfile) ?? 512' in view
assert 'apiRuntime.context = selectedAPIContext' in view

# Changing Context/Profile while the listener is paused must reload the runtime
# rather than silently resuming the old resident context.
for marker in [
    "selectedAPIContextValue",
    "selectedAPIRuntimeProfileValue",
    "preservedRuntimeMatchesAPISelection",
    "应用设置并重新预热 API",
    "API Context/Profile 已变更，正在重新预热",
]:
    assert marker in view
assert "guard preservedRuntimeMatchesAPISelection else" in view
assert "apiServer.stop()" in view
assert "startAPIServer()" in view

# Discovery metadata must expose fields consumed by OpenAI-compatible clients.
for marker in [
    '"name": "Bonsai 2 27B Local"',
    '"context_length": contextWindow',
    '"context_window": contextWindow',
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
assert '"created": 0' in server

# Multi-turn OpenAI compatibility: preserve developer/system instructions,
# compile previous user/assistant turns, and keep the latest user turn current.
for marker in [
    '"developer"',
    "Conversation history:\\n",
    '"User: " + message.text',
    '"Assistant: " + message.text',
    "normalizedMessages.lastIndex",
    'root["max_output_tokens"]',
]:
    assert marker in server

# tool_choice=none must be a safe compatibility mode, but actual tool calls
# remain unsupported.
assert 'toolChoiceName != "none"' in server
assert 'message["tool_calls"]' in server
assert "unsupportedTools" in server

# Visual follow-up chats may reuse the most recent prior user image turn while
# keeping the latest text-only user turn as the active question.
for marker in [
    "imageMessageIndices",
    "visualUserIndex",
    "visualUser?.images ?? []",
    "visualUser?.ordering ?? .none",
    "active visual context for the",
]:
    assert marker in server
assert "totalImages = max(" in server
assert "OpenAIMultimodalMessageBindingValidator" in server

# User-facing copy config must state the exact client capability contract.
for marker in [
    "Chatbox",
    "Vision: ON",
    "Reasoning: OFF",
    "Tool Use: OFF",
    "Context Window:",
]:
    assert marker in view

# HTTP transport must accept both Content-Length and chunked request bodies.
for marker in [
    'headers["transfer-encoding"]',
    '.contains("chunked")',
    "decodeChunkedBody(",
    'split(separator: ";", maxSplits: 1)',
]:
    assert marker in server

# Parse errors are machine-readable and 5xx failures are server_error.
for marker in [
    "catch let error as APIServerError",
    "var code: String",
    '"tools_not_supported"',
    '"unsupported_message_role"',
    '"unsupported_response_format"',
    '"invalid_parameter"',
    '"server_error"',
]:
    assert marker in server

# Browser/local clients may use either Bearer or X-API-Key.
assert 'request.headers["authorization"] == expected' in server
assert 'request.headers["x-api-key"] == apiKey' in server
assert "OpenAI-Organization" in server
assert "OpenAI-Project" in server
for header in [
    "OpenAI-Beta",
    "X-Stainless-Lang",
    "X-Stainless-Package-Version",
    "X-Stainless-Runtime",
    "X-Stainless-Timeout",
    "Access-Control-Allow-Private-Network: true",
]:
    assert header in server

# Client observability must distinguish transport attempts from admitted inference.
for marker in [
    "requestAttemptCount",
    "rejectedRequestCount",
    "lastRequestPath",
    "lastRejectionCode",
]:
    assert marker in server
    assert marker in view
assert "recordRejection(" in server

# response_format=text is accepted; structured output is explicitly rejected.
assert 'root["response_format"]' in server
assert 'type != "text"' in server
assert "unsupportedResponseFormat" in server
assert '"param": param ?? NSNull()' in server
for name in [
    "stop",
    "frequency_penalty",
    "presence_penalty",
    "logprobs",
    "top_logprobs",
]:
    assert name in server
assert "unsupportedParameter" in server

# Text and vision overflow must converge on the same client-visible error.
assert view.count('"context_length_exceeded"') >= 2
assert "let metrics: GenerationMetrics" in view
assert "catch let error as LabError" in view

# Build 60 invariants remain.
assert 'request.path == "/v1/chat/completions"' in server
assert 'request.path == "/v1/models"' in server
assert "unsupportedTools" in server
assert "context_length_exceeded" in view

# Device probes must keep all generated evidence on D:, never in the Windows
# user temp directory.
assert r'D:\apple\re_output\rc1252-context-boundary' in boundary_probe
assert '$env:TEMP' not in boundary_probe
assert "SUMMARY-boundary-" in boundary_probe
assert "context_length" in boundary_probe
assert r'D:\apple\re_output\rc1252-context-probe' in probe
assert '$env:TEMP' not in probe
assert "SUMMARY-context-" in probe
assert "context_length" in probe
assert "context_length_exceeded" in probe
assert "tools_not_supported" in probe

# Official-style Python/JS SDK probes are part of the deliverable and must also
# keep evidence on D: by default.
for sdk_probe in [py_sdk_probe, js_sdk_probe]:
    assert "D:" in sdk_probe
    assert "re_output" in sdk_probe
    assert "models.list" in sdk_probe
    assert "chat.completions.create" in sdk_probe
    assert "stream" in sdk_probe
assert "tool_choice" in py_sdk_probe
assert "tool_choice" in js_sdk_probe

# CI must execute this contract and package Build 61.
assert "python3 tools/rc1252_api_usability_contract_tests.py" in workflow
assert "RC1.25.2_CLIENT_COMPATIBILITY_MATRIX.md" in workflow
assert "tools/rc1252_context_boundary_probe.ps1" in workflow
assert "tools/rc1252_context_ladder_device_probe.ps1" in workflow
assert "tools/rc1252_openai_python_sdk_probe.py" in workflow
assert "tools/rc1252_openai_js_sdk_probe.mjs" in workflow
assert 'CFBundleVersion raw -o - "$APP/Info.plist")" = "61"' in workflow

print("RC1.25.2 Build 61 API usability contracts: PASS")
