from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
view = (root / "BonsaiLab" / "ProductionView.swift").read_text()
project = (root / "project.yml").read_text()
workflow = (root / ".github" / "workflows" / "build-ios.yml").read_text()

assert (
    'Text("1.0 · RC1.24.1 Runtime Profile A/B")' in view
    or 'Text("1.0 · RC1.25.0 Multi-Image OpenAI API")' in view
    or 'Text("1.0 · RC1.25.1 API Hardening")' in view
    or 'Text("1.0 · RC1.25.2 Build 63 Vision Lifecycle Safety")' in view
    or 'Text("1.0 · RC1.25.3 Build 64 Native Prefill Isolation")' in view
    or 'Text("1.0 · RC1.26 Build 65 Runtime Optimization Lab")' in view

    or 'Text("1.0 · RC1.26 Build 66 Memory Governor Observer")' in view
)
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

runtime_switch = view.index("switch selectedAPIRuntimeProfile")
flash_case = view.index('case "ab_flash_only":', runtime_switch)
kqv_case = view.index('case "ab_flash_kqv":', flash_case)
full_case = view.index('case "accelerated":', kqv_case)

flash_block = view[flash_case:kqv_case]
assert 'apiRuntime.flashAttention = true' in flash_block
assert 'apiRuntime.offloadKQV = false' in flash_block
assert 'apiRuntime.opOffload = false' in flash_block

kqv_block = view[kqv_case:full_case]
assert 'apiRuntime.flashAttention = true' in kqv_block
assert 'apiRuntime.offloadKQV = true' in kqv_block
assert 'apiRuntime.opOffload = false' in kqv_block

# Production default is unchanged.
assert 'private var apiRuntimeProfile = "accelerated"' in view

match = re.search(r'CURRENT_PROJECT_VERSION:\s*"([0-9]+)"', project)
assert match is not None
assert int(match.group(1)) >= 56

assert "lab-v1-rc1-24-1-build56-runtime-profile-ab" in workflow
assert "RC1.24.1 runtime profile A/B contracts" in workflow
assert "tools/rc1241_runtime_profile_ab_contract_tests.py" in workflow
assert "tools/rc1241_runtime_profile_ab_contract_tests.py" in workflow

print("RC1.24.1 Build 56 runtime profile A/B contracts: PASS")
