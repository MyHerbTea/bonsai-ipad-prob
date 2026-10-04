from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
header = (root / "BonsaiLab" / "StagedVisionBridge.h").read_text()
bridge = (root / "BonsaiLab" / "StagedVisionBridge.mm").read_text()
types = (root / "BonsaiLab" / "LabTypes.swift").read_text()
engine = (root / "BonsaiLab" / "BonsaiEngine.swift").read_text()
view = (root / "BonsaiLab" / "ProductionView.swift").read_text()
project = (root / "project.yml").read_text()
workflow = (root / ".github" / "workflows" / "build-ios.yml").read_text()

# RC1.23.5 Phase A is observability-only. Existing RC1.23.4 telemetry semantics
# must remain intact while new fields are namespaced with rc1235_.
for field in [
    '"requested_max_tokens=',
    '"effective_max_tokens=',
    '"termination_reason=',
    '"finish_reason=',
    '"suffix_prefill_ms=',
]:
    assert field in view

for native_field in [
    "suffix_token_count",
    "suffix_decode_calls",
    "suffix_batch_capacity",
    "suffix_last_batch_tokens",
    "suffix_batch_utilization",
]:
    assert re.search(rf"\b{native_field}\b", header)

assert "struct TextChunkDecodeProfile" in bridge
assert re.search(
    r"TextChunkDecodeProfile\s*\*\s*profile\s*=\s*nullptr",
    bridge,
)
assert re.search(r"profile->decode_calls\s*\+=\s*1", bridge)
assert re.search(r"profile->last_batch_tokens\s*=\s*count", bridge)
assert re.search(r"TextChunkDecodeProfile\s+suffix_profile", bridge)
assert re.search(
    r"decode_text_chunk\([^;]*&suffix_profile",
    bridge,
    flags=re.S,
)

for assignment in [
    "result.suffix_token_count",
    "result.suffix_decode_calls",
    "result.suffix_batch_capacity",
    "result.suffix_last_batch_tokens",
    "result.suffix_batch_utilization",
]:
    assert assignment in bridge

vision_start = types.index("struct VisionMetrics: Sendable {")
vision_end = types.index("enum LabError:", vision_start)
vision = types[vision_start:vision_end]
for swift_field in [
    "suffixTokenCount",
    "suffixDecodeCalls",
    "suffixBatchCapacity",
    "suffixUBatchCapacity",
    "suffixLastBatchTokens",
    "suffixBatchUtilization",
]:
    assert re.search(rf"let\s+{swift_field}\s*:", vision)

for pattern in [
    r"suffixTokenCount:\s*Int\(prefill\.suffix_token_count\)",
    r"suffixDecodeCalls:\s*Int\(prefill\.suffix_decode_calls\)",
    r"suffixBatchCapacity:\s*Int\(prefill\.suffix_batch_capacity\)",
    r"suffixUBatchCapacity:\s*appliedRuntime\.ubatch",
    r"suffixLastBatchTokens:\s*Int\(prefill\.suffix_last_batch_tokens\)",
    r"suffixBatchUtilization:\s*prefill\.suffix_batch_utilization",
]:
    assert re.search(pattern, engine)

for field in [
    '"rc1235_suffix_tokens=',
    '"rc1235_suffix_decode_calls=',
    '"rc1235_suffix_batch_capacity=',
    '"rc1235_suffix_ubatch_capacity=',
    '"rc1235_suffix_last_batch_tokens=',
    '"rc1235_suffix_batch_utilization=',
    '"rc1235_suffix_ms_per_decode_call=',
]:
    assert field in view

# The new build must be distinct from the frozen Build 46 executable.
build_match = re.search(
    r'CURRENT_PROJECT_VERSION:\s*"(?P<build>\d+)"',
    project,
)
assert build_match is not None
assert int(build_match.group("build")) >= 47

# The new branch and contract must be covered by CI.
assert "lab-v1-rc1-23-5-ttft-suffix-prefill-efficiency" in workflow
assert "RC1.23.5 suffix prefill profiling contracts" in workflow
assert "tools/rc1235_suffix_prefill_profiling_contract_tests.py" in workflow

print("RC1.23.5 Build 47 suffix prefill profiling contracts: PASS")
