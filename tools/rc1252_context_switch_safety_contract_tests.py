from pathlib import Path

root = Path(__file__).resolve().parents[1]
engine = (root / "BonsaiLab" / "BonsaiEngine.swift").read_text(encoding="utf-8")
sidecar = (root / "BonsaiLab" / "BonsaiMLXVisionSidecar.swift").read_text(encoding="utf-8")
view = (root / "BonsaiLab" / "ProductionView.swift").read_text(encoding="utf-8")
project = (root / "project.yml").read_text(encoding="utf-8")
workflow = (root / ".github" / "workflows" / "build-ios.yml").read_text(encoding="utf-8")

assert (
    'CURRENT_PROJECT_VERSION: "63"' in project
    or 'CURRENT_PROJECT_VERSION: "64"' in project
    or 'CURRENT_PROJECT_VERSION: "65"' in project
    or 'CURRENT_PROJECT_VERSION: "66"' in project
    or 'CURRENT_PROJECT_VERSION: "67"' in project
    or 'CURRENT_PROJECT_VERSION: "68"' in project
    or 'CURRENT_PROJECT_VERSION: "69"' in project
    or 'CURRENT_PROJECT_VERSION: "70"' in project
    or 'CURRENT_PROJECT_VERSION: "71"' in project
    or 'CURRENT_PROJECT_VERSION: "72"' in project
    or 'CURRENT_PROJECT_VERSION: "75"' in project
)
assert (
    "RC1.25.2 Build 63 Vision Lifecycle Safety" in view
    or "RC1.25.3 Build 64 Native Prefill Isolation" in view
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
)

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
    'CFBundleVersion raw -o - "$APP/Info.plist")" = "63"' in workflow
    or 'CFBundleVersion raw -o - "$APP/Info.plist")" = "64"' in workflow
    or 'CFBundleVersion raw -o - "$APP/Info.plist")" = "65"' in workflow
    or 'CFBundleVersion raw -o - "$APP/Info.plist")" = "66"' in workflow
    or 'CFBundleVersion raw -o - "$APP/Info.plist")" = "67"' in workflow
    or 'CFBundleVersion raw -o - "$APP/Info.plist")" = "68"' in workflow
    or 'CFBundleVersion raw -o - "$APP/Info.plist")" = "69"' in workflow
    or 'CFBundleVersion raw -o - "$APP/Info.plist")" = "70"' in workflow
    or 'CFBundleVersion raw -o - "$APP/Info.plist")" = "71"' in workflow
    or 'CFBundleVersion raw -o - "$APP/Info.plist")" = "72"' in workflow
    or 'CFBundleVersion raw -o - "$APP/Info.plist")" = "75"' in workflow
)

print("RC1.25.2 Build 63 context switch safety contracts: PASS")
