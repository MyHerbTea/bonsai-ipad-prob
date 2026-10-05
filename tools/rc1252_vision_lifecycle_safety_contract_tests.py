from pathlib import Path

root = Path(__file__).resolve().parents[1]
engine = (root / "BonsaiLab" / "BonsaiEngine.swift").read_text(encoding="utf-8")
sidecar = (root / "BonsaiLab" / "BonsaiMLXVisionSidecar.swift").read_text(encoding="utf-8")
view = (root / "BonsaiLab" / "ProductionView.swift").read_text(encoding="utf-8")
server = (root / "BonsaiLab" / "LocalOpenAIServer.swift").read_text(encoding="utf-8")
project = (root / "project.yml").read_text(encoding="utf-8")
workflow = (root / ".github" / "workflows" / "build-ios.yml").read_text(encoding="utf-8")

assert (
    'CURRENT_PROJECT_VERSION: "63"' in project
    or 'CURRENT_PROJECT_VERSION: "64"' in project
    or 'CURRENT_PROJECT_VERSION: "65"' in project
    or 'CURRENT_PROJECT_VERSION: "66"' in project
    or 'CURRENT_PROJECT_VERSION: "67"' in project
    or 'CURRENT_PROJECT_VERSION: "68"' in project
)
assert (
    "RC1.25.2 Build 63 Vision Lifecycle Safety" in view
    or "RC1.25.3 Build 64 Native Prefill Isolation" in view
    or 'Text("1.0 · RC1.26 Build 65 Runtime Optimization Lab")' in view

    or 'Text("1.0 · RC1.26 Build 66 Memory Governor Observer")' in view


    or 'Text("1.0 · RC1.26 Build 67 Request Lifecycle Governor Observer")' in view



    or 'Text("1.0 · RC1.26 Build 68 Heap Pressure Relief")' in view
    or 'Text("1.0 · RC1.26 Build 69 Metal Prefill Measurement")' in view
)
assert (
    "RC1.25.2 Build 63 API Context Ladder" in view
    or "RC1.25.3 Build 64 API Context Ladder" in view
)

# A fresh vision encode must not begin while request-local KV from the previous
# text/vision request is still live in the 27B context.
for marker in [
    "func prepareForAPIVisionEncode()",
    "llama_memory_clear(",
]:
    assert marker in engine

assert (
    "API_VISION_00_CONTEXT_CLEARED_BEFORE_MLX" in engine
    or "API_VISION_01_CONTEXT_CLEARED_BEFORE_MLX" in engine
)
assert (
    "BonsaiRC1252VisionPreEncode" in engine
    or "BonsaiRC1253VisionPreEncode" in engine
)

prepare = engine[
    engine.index("func prepareForAPIVisionEncode()"):
    engine.index("func finishAPIVisionRequestSuccess()")
]
assert "llama_memory_clear" in prepare
assert "unloadAll" not in prepare
assert "llama_model_free" not in prepare

# Successful vision requests must release request-local KV before returning,
# while keeping the resident model/context objects allocated.
finish = engine[
    engine.index("func finishAPIVisionRequestSuccess()"):
    engine.index("func cleanupAfterRequestFailure()")
]
assert "llama_memory_clear" in finish
assert "API_VISION_99_CONTEXT_CLEARED_AFTER_SUCCESS" in finish
assert "unloadAll" not in finish
assert "llama_free" not in finish
assert "llama_model_free" not in finish

# Product ordering: pre-encode drain occurs before MLX encode; successful
# cleanup occurs after metrics and before OpenAIHandlerResult is returned.
pre_idx = view.index(".prepareForAPIVisionEncode()")
encode_idx = view.index(".encodeForInjection(", pre_idx)
assert pre_idx < encode_idx

persist_idx = view.index(".persistVisionSuccess(", encode_idx)
finish_idx = view.index(".finishAPIVisionRequestSuccess()", persist_idx)
sidecar_cleanup_idx = view.index(".cleanupAfterRequestSuccess()", finish_idx)
return_idx = view.index("return OpenAIHandlerResult(", sidecar_cleanup_idx)
assert persist_idx < finish_idx < sidecar_cleanup_idx < return_idx

for stage in [
    "pre_encode_context_drain",
    "mlx_encode_begin",
    "mlx_encode_done",
    "native_prefill_begin",
    "success_cleanup_begin",
    "complete",
]:
    assert stage in view

assert "func cleanupAfterRequestSuccess()" in sidecar
assert 'mark("MLX_API_SUCCESS_CLEANUP")' in sidecar

# /health must expose the persisted last crash stage so a resumed external
# harness can collect evidence after an app relaunch.
for marker in [
    '"diagnostics": [',
    '"last_engine_stage"',
    '"last_mlx_vision_stage"',
    '"vision_request_stage"',
    '"context_switch_state"',
    '"last_api_image_count"',
    '"last_multi_image_layout"',
]:
    assert marker in server

assert "python3 tools/rc1252_vision_lifecycle_safety_contract_tests.py" in workflow
assert (
    'CFBundleVersion raw -o - "$APP/Info.plist")" = "63"' in workflow
    or 'CFBundleVersion raw -o - "$APP/Info.plist")" = "64"' in workflow
    or 'CFBundleVersion raw -o - "$APP/Info.plist")" = "65"' in workflow
    or 'CFBundleVersion raw -o - "$APP/Info.plist")" = "66"' in workflow
    or 'CFBundleVersion raw -o - "$APP/Info.plist")" = "67"' in workflow
    or 'CFBundleVersion raw -o - "$APP/Info.plist")" = "68"' in workflow
)

print("RC1.25.2 Build 63 vision lifecycle safety contracts: PASS")
