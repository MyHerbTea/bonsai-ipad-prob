from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
engine = (root / "BonsaiLab" / "BonsaiEngine.swift").read_text(encoding="utf-8")
sidecar = (root / "BonsaiLab" / "BonsaiMLXVisionSidecar.swift").read_text(encoding="utf-8")
view = (root / "BonsaiLab" / "ProductionView.swift").read_text(encoding="utf-8")
project = (root / "project.yml").read_text(encoding="utf-8")
workflow = (root / ".github" / "workflows" / "build-ios.yml").read_text(encoding="utf-8")

project_build_match = re.search(
    r'CURRENT_PROJECT_VERSION:\s*"(?P<build>\d+)"',
    project,
)
assert project_build_match is not None
project_build = int(project_build_match.group("build"))
assert project_build >= 63
assert "RC1.26" in view
assert f"Build {project_build}" in view

# The risky old path reloaded the full 27B model after a paused-listener context
# change. The new path must keep the mmap-backed model resident and recreate only
# the llama context.
assert "reconfigureAPIRuntimePreservingModel()" in view
assert "reconfigureTextContextKeepingModel(" in view
assert "releaseResidentStateForContextSwitch()" in view
assert "27B model 未重载" in view

mismatch = view[
    view.index("guard preservedRuntimeMatchesAPISelection else"):
    view.index("let activeContext =", view.index("guard preservedRuntimeMatchesAPISelection else"))
]
assert "reconfigureAPIRuntimePreservingModel()" in mismatch
assert "apiServer.stop()" not in mismatch
assert "startAPIServer()" not in mismatch

switch_impl = engine[
    engine.index("func reconfigureTextContextKeepingModel("):
    engine.index("func loadVision(", engine.index("func reconfigureTextContextKeepingModel("))
]
assert "llama_free(context)" in switch_impl
assert "makeContext(" in switch_impl
assert "llama_model_free" not in switch_impl
assert "unloadAll()" not in switch_impl
assert "CTX_SWITCH_03_CONTEXT_CREATE_BEGIN_CTX_" in switch_impl
assert "CTX_SWITCH_04_READY_CTX_" in switch_impl
assert "CTX_SWITCH_91_ROLLBACK_READY_CTX_" in switch_impl
assert "BonsaiRC1252ContextSwitchState" in switch_impl

assert "func releaseResidentStateForContextSwitch()" in sidecar
assert "model = nil" in sidecar
assert "loadedWeightsPath = nil" in sidecar
assert "Memory.clearCache()" in sidecar

# Diagnostic snapshot must make a future crash stage visible after relaunch.
for marker in [
    "rc1252_context_switch_state=",
    "rc1252_context_switch_from=",
    "rc1252_context_switch_to=",
]:
    assert marker in view

assert "python3 tools/rc1252_context_switch_safety_contract_tests.py" in workflow
assert (
    f'CFBundleVersion raw -o - "$APP/Info.plist")" = "{project_build}"'
    in workflow
)
print("RC1.25.2 Build 63 context switch safety contracts: PASS")
