from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
view = (root / "BonsaiLab" / "ProductionView.swift").read_text()
project = (root / "project.yml").read_text()
workflow = (root / ".github" / "workflows" / "build-ios.yml").read_text()

# Phase B must keep 512 as the default and expose 256 only as an explicit
# pre-start experimental selector.
assert re.search(
    r'@AppStorage\("BonsaiRC1235APIContextProfile"\)\s*'
    r'private\s+var\s+apiContextProfile\s*=\s*"512"',
    view,
)
assert '"实验：API Context"' in view
assert 'Text("512 Baseline").tag("512")' in view
assert 'Text("256 Experimental").tag("256")' in view

# The selector must not be changeable while the API is running.
context_picker = re.search(
    r'Picker\(\s*"实验：API Context"[\s\S]*?\.disabled\(apiServer\.isRunning\)',
    view,
)
assert context_picker is not None

# Runtime selection must be derived from the selector, with any unknown/stale
# value conservatively falling back to 512.
assert re.search(
    r'let\s+selectedAPIContext\s*=\s*'
    r'apiContextProfile\s*==\s*"256"\s*\?\s*256\s*:\s*512',
    view,
)
assert re.search(
    r'apiRuntime\.context\s*=\s*selectedAPIContext',
    view,
)

# The actual active context must be persisted after successful model load so
# diagnostics can distinguish requested vs running configuration.
assert '"BonsaiRC1235ActiveAPIContext"' in view
assert re.search(
    r'UserDefaults\.standard\.set\(\s*'
    r'selectedAPIContext,\s*'
    r'forKey:\s*"BonsaiRC1235ActiveAPIContext"\s*\)',
    view,
    flags=re.S,
)

# Diagnostics must no longer hard-code api_context=512.
assert '"api_context=512"' not in view
assert '"api_context=\\(effectiveAPIContext)"' in view
assert '"rc1235_api_context_requested=\\(requestedAPIContext)"' in view
assert '"rc1235_api_context_active=\\(activeAPIContext)"' in view
assert '"rc1235_api_context_profile=\\(requestedAPIContextProfile)"' in view

# 512 remains the default. No automatic admission-driven context policy belongs
# in this proof candidate.
assert 'private var apiContextProfile = "512"' in view
assert "dynamicContext" not in view
assert "automaticContext" not in view

# Build 48 is a distinct A/B executable.
build_match = re.search(
    r'CURRENT_PROJECT_VERSION:\s*"(?P<build>\d+)"',
    project,
)
assert build_match is not None
assert int(build_match.group("build")) >= 48

# CI must cover this branch and Phase B contract.
assert "lab-v1-rc1-23-5-ttft-suffix-prefill-efficiency" in workflow
assert "RC1.23.5 dynamic context A/B contracts" in workflow
assert "tools/rc1235_dynamic_context_ab_contract_tests.py" in workflow
assert 'CFBundleVersion raw -o - "$APP/Info.plist")" = "48"' in workflow
assert "Build48-Dynamic-Context-AB-Candidate" in workflow

print("RC1.23.5 Build 48 dynamic context A/B contracts: PASS")
