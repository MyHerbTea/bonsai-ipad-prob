from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
view = (root / "BonsaiLab" / "ProductionView.swift").read_text()
project = (root / "project.yml").read_text()
workflow = (root / ".github" / "workflows" / "build-ios.yml").read_text()

assert 'Text("1.0 · RC1.24.1 Runtime Profile A/B")' in view
assert 'Text("Safe").tag("safe")' in view
assert 'Text("Flash").tag("ab_flash_only")' in view
assert 'Text("+KQV").tag("ab_flash_kqv")' in view
assert 'Text("Full").tag("accelerated")' in view

# Build 56 is a controlled cumulative ladder:
# Safe -> Flash only -> Flash+KQV -> Full (+Op Offload)
for marker in [
    'case "ab_flash_only":',
    'case "ab_flash_kqv":',
    'case "accelerated":',
    'apiRuntime.flashAttention = true',
    'apiRuntime.offloadKQV = true',
    'apiRuntime.opOffload = true',
]:
    assert marker in view

flash_block = view[
    view.index('case "ab_flash_only":'):
    view.index('case "ab_flash_kqv":')
]
assert 'apiRuntime.flashAttention = true' in flash_block
assert 'apiRuntime.offloadKQV = false' in flash_block
assert 'apiRuntime.opOffload = false' in flash_block

kqv_block = view[
    view.index('case "ab_flash_kqv":'):
    view.index('case "accelerated":', view.index('case "ab_flash_kqv":'))
]
assert 'apiRuntime.flashAttention = true' in kqv_block
assert 'apiRuntime.offloadKQV = true' in kqv_block
assert 'apiRuntime.opOffload = false' in kqv_block

# Production default is unchanged.
assert 'private var apiRuntimeProfile = "accelerated"' in view

match = re.search(r'CURRENT_PROJECT_VERSION:\s*"([0-9]+)"', project)
assert match is not None
assert int(match.group(1)) == 56

assert "lab-v1-rc1-24-1-build56-runtime-profile-ab" in workflow
assert "RC1.24.1 runtime profile A/B contracts" in workflow
assert "tools/rc1241_runtime_profile_ab_contract_tests.py" in workflow
assert 'CFBundleVersion raw -o - "$APP/Info.plist")" = "56"' in workflow
assert "Build56-Runtime-Profile-AB" in workflow

print("RC1.24.1 Build 56 runtime profile A/B contracts: PASS")
