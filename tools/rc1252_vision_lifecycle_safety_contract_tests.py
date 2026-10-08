from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
engine = (root / "BonsaiLab" / "BonsaiEngine.swift").read_text(encoding="utf-8")
sidecar = (root / "BonsaiLab" / "BonsaiMLXVisionSidecar.swift").read_text(encoding="utf-8")
view = (root / "BonsaiLab" / "ProductionView.swift").read_text(encoding="utf-8")
server = (root / "BonsaiLab" / "LocalOpenAIServer.swift").read_text(encoding="utf-8")
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

assert (
    "RC1.25.2 Build 63 API Context Ladder" in view
    or "RC1.25.3 Build 64 API Context Ladder" in view
    or "RC1.26 Build 75 API 冷启动保护" in view
    or "RC1.26 Build 76 M5 Extreme Text KV Lab" in view
    or "RC1.26 Build 77 M5 Extended Context Lab" in view
    or "RC1.26 Build 78 M5 Context Boundary Lab" in view
    or "RC1.26 Build 79 Storage-Memory Long Context Lab" in view
    or "RC1.26 Build 80 Long-Context Tier Reload Fix" in view
    or "RC1.26 Build 81 32K Memory Squeeze" in view
    or "RC1.26 Build 82 Unified-Metal 32K Lab" in view
    or "RC1.26 Build 86 Crash Forensics V2" in view
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
    f'CFBundleVersion raw -o - "$APP/Info.plist")" = "{project_build}"'
    in workflow
)
print("RC1.25.2 Build 63 vision lifecycle safety contracts: PASS")
