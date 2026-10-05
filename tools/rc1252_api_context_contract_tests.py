from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
types = (root / "BonsaiLab" / "LabTypes.swift").read_text()
view = (root / "BonsaiLab" / "ProductionView.swift").read_text()
server = (root / "BonsaiLab" / "LocalOpenAIServer.swift").read_text()
project = (root / "project.yml").read_text()
workflow = (root / ".github" / "workflows" / "build-ios.yml").read_text()

# Build 61 introduces an explicit bounded API-context exploration surface while
# preserving the certified 512 profile as the default.
assert "enum APIContextProfile" in types
for marker in [
    'case baseline512 = "512"',
    'case extended768 = "768"',
    'case balanced1024 = "1024"',
    'case long2048 = "2048"',
]:
    assert marker in types

assert 'private var apiContextProfile = "512"' in view
assert 'Picker(' in view
assert '"实验：API Context"' in view
assert "APIContextProfile.allCases" in view
assert ".disabled(apiServer.isRunning)" in view
assert "APIContextProfile.normalized(apiContextProfile)" in view
assert "selectedAPIContext" in view
assert "apiRuntime.context = selectedAPIContext" in view

# Invalid persisted values may normalize back to 512, but valid 768/1024/2048
# selections must no longer be forcibly reset on app appearance.
assert 'if APIContextProfile(rawValue: apiContextProfile) == nil' in view
assert 'if apiContextProfile != "512"' not in view

# The active runtime context is persisted before the listener is started so
# /v1/models can advertise the exact running capability.
active_set = view.index('"BonsaiRC1235ActiveAPIContext"')
server_start = view.index("try apiServer.start(port: 8080)")
assert active_set < server_start

# /v1/models and /v1/models/{id} share modelObject(), which now exposes
# compatibility metadata from the active runtime rather than a guessed value.
assert '"context_window": contextWindow' in server
assert '"max_output_tokens": 256' in server
assert '"max_images_per_request": 3' in server
for marker in [
    '"chat": true',
    '"vision": true',
    '"streaming": true',
    '"multi_image": true',
    '"tools": false',
    '"reasoning": false',
    '"responses_api": false',
]:
    assert marker in server
assert '"compatibility": "openai_chat_completions"' in server

# Release identity.
assert 'Text("1.0 · RC1.25.2 API Compatibility")' in view
assert "RC1.25.2 Build 61 API Compatibility" in view
match = re.search(r'CURRENT_PROJECT_VERSION:\s*"([0-9]+)"', project)
assert match is not None
assert int(match.group(1)) == 61

assert "RC1.25.2 API context compatibility contracts" in workflow
assert "tools/rc1252_api_context_contract_tests.py" in workflow
assert 'CFBundleVersion raw -o - "$APP/Info.plist")" = "61"' in workflow
assert "Build61-API-Compatibility" in workflow

print("RC1.25.2 Build 61 API context compatibility contracts: PASS")
