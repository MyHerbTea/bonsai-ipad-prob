from pathlib import Path

root = Path(__file__).resolve().parents[1]
engine = (root / "BonsaiLab" / "BonsaiEngine.swift").read_text(encoding="utf-8")
bridge_h = (root / "BonsaiLab" / "StagedVisionBridge.h").read_text(encoding="utf-8")
bridge_mm = (root / "BonsaiLab" / "StagedVisionBridge.mm").read_text(encoding="utf-8")
view = (root / "BonsaiLab" / "ProductionView.swift").read_text(encoding="utf-8")
server = (root / "BonsaiLab" / "LocalOpenAIServer.swift").read_text(encoding="utf-8")
project = (root / "project.yml").read_text(encoding="utf-8")
workflow = (root / ".github" / "workflows" / "build-ios.yml").read_text(encoding="utf-8")

assert (
    'CURRENT_PROJECT_VERSION: "64"' in project
    or 'CURRENT_PROJECT_VERSION: "65"' in project
    or 'CURRENT_PROJECT_VERSION: "66"' in project
    or 'CURRENT_PROJECT_VERSION: "67"' in project
    or 'CURRENT_PROJECT_VERSION: "68"' in project
    or 'CURRENT_PROJECT_VERSION: "69"' in project
)
assert (
    "RC1.25.3 Build 64 Native Prefill Isolation" in view
    or 'Text("1.0 · RC1.26 Build 65 Runtime Optimization Lab")' in view

    or 'Text("1.0 · RC1.26 Build 66 Memory Governor Observer")' in view


    or 'Text("1.0 · RC1.26 Build 67 Request Lifecycle Governor Observer")' in view



    or 'Text("1.0 · RC1.26 Build 68 Heap Pressure Relief")' in view
    or 'Text("1.0 · RC1.26 Build 69 Metal Prefill Measurement")' in view
)

assert "void BonsaiClearVisionPrefixKVSnapshot(void);" in bridge_h
assert "void BonsaiClearVisionPrefixKVSnapshot(void)" in bridge_mm

prepare_start = engine.index("func prepareForAPIVisionEncode()")
prepare_end = engine.index("func finishAPIVisionRequestSuccess()", prepare_start)
prepare = engine[prepare_start:prepare_end]
assert "BonsaiClearVisionPrefixKVSnapshot()" in prepare
assert "apiVisionPrefixReuseKey = nil" in prepare
assert "apiVisionPrefixPositions = 0" in prepare
assert "llama_memory_clear" in prepare
assert prepare.index("BonsaiClearVisionPrefixKVSnapshot()") < prepare.index("llama_memory_clear")

api_anchor = view.index("enablePrefixReuse:")
api_slice = view[api_anchor:api_anchor + 500]
assert "false" in api_slice
assert "UserDefaults.standard" not in api_slice
assert "let prefixReuseEnabled = false" in view

for stage in [
    "TWOPHASE_B00_ENTER",
    "TWOPHASE_B01_CACHE_LOADED",
    "TWOPHASE_B02_ADMISSION_PASS",
    "TWOPHASE_B03_PREFIX_REUSE_CHECK",
    "TWOPHASE_B03_PREFIX_STATE_CLEARED",
    "TWOPHASE_B10_PREFIX_TEXT_BEGIN",
    "TWOPHASE_B11_PREFIX_TEXT_DONE",
    "TWOPHASE_B20_IMAGE_EMBED_BEGIN",
    "TWOPHASE_B21_IMAGE_EMBED_DONE",
    "TWOPHASE_B22_PREFIX_SNAPSHOT_SAVE_BEGIN",
    "TWOPHASE_B30_SUFFIX_TEXT_BEGIN",
    "TWOPHASE_B31_SUFFIX_TEXT_DONE",
]:
    assert stage in bridge_mm

for marker in [
    '"last_two_phase_vision_stage"',
    '"configured_vision_prefix_kv_reuse_enabled"',
    '"api_vision_prefix_reuse_effective"',
    "persistedSupportText",
]:
    assert marker in server

assert "python3 tools/rc1253_native_prefill_isolation_contract_tests.py" in workflow
assert (
    'CFBundleVersion raw -o - "$APP/Info.plist")" = "64"' in workflow
    or 'CFBundleVersion raw -o - "$APP/Info.plist")" = "65"' in workflow
    or 'CFBundleVersion raw -o - "$APP/Info.plist")" = "66"' in workflow
    or 'CFBundleVersion raw -o - "$APP/Info.plist")" = "67"' in workflow
    or 'CFBundleVersion raw -o - "$APP/Info.plist")" = "68"' in workflow
)

print("RC1.25.3 Build 64 native prefill isolation contracts: PASS")
