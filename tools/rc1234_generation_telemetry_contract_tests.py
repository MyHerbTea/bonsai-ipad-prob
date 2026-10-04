from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
types = (root / "BonsaiLab" / "LabTypes.swift").read_text()
engine = (root / "BonsaiLab" / "BonsaiEngine.swift").read_text()
view = (root / "BonsaiLab" / "ProductionView.swift").read_text()
project = (root / "project.yml").read_text()
probe = (root / "tools" / "rc1234_generation_probe.ps1").read_text()

metrics_start = types.index("struct GenerationMetrics: Sendable {")
metrics_end = types.index("struct ModelMetrics: Sendable {", metrics_start)
metrics = types[metrics_start:metrics_end]

assert "enum GenerationTerminationReason: String, Sendable" in types
assert re.search(r"\bcase\s+eog\b", types)
assert re.search(r"\bcase\s+length\b", types)
assert "var openAIFinishReason: String" in types

assert re.search(r"let\s+effectiveMaxTokens:\s*Int", metrics)
assert re.search(
    r"let\s+terminationReason:\s*GenerationTerminationReason",
    metrics,
)

assert len(
    re.findall(
        r"terminationReason:\s*generated\.terminationReason",
        engine,
    )
) >= 3
assert re.search(
    r"var\s+terminationReason:\s*GenerationTerminationReason\s*=\s*\.length",
    engine,
)
assert re.search(r"terminationReason\s*=\s*\.eog", engine)
assert engine.count("effectiveMaxTokens:") >= 3

assert len(re.findall(r"requestedMaxTokens:\s*Int", view)) >= 2
assert len(
    re.findall(
        r"requestedMaxTokens:\s*payload\.maxTokens",
        view,
    )
) >= 2

for field in [
    '"requested_max_tokens=',
    '"effective_max_tokens=',
    '"termination_reason=',
    '"finish_reason=',
]:
    assert view.count(field) >= 2

assert len(
    re.findall(
        r"finishReason:\s*metrics(?:\.generation)?"
        r"\s*\.terminationReason\s*\.openAIFinishReason",
        view,
    )
) >= 2

assert not re.search(
    r"generatedTokens\s*>=\s*gen\.maxTokens",
    view,
)

build_match = re.search(
    r'CURRENT_PROJECT_VERSION:\s*"(?P<build>\d+)"',
    project,
)
assert build_match is not None
assert int(build_match.group("build")) >= 46

# Windows PowerShell 5.1 probe must be source-encoding agnostic and force UTF-8
# for both request and response payloads.
assert all(ord(ch) < 128 for ch in probe)
assert "application/json; charset=utf-8" in probe
assert "[System.Text.Encoding]::UTF8.GetBytes($bodyJson)" in probe
assert "System.IO.StreamReader" in probe
assert "[System.Text.Encoding]::UTF8" in probe
assert "[Convert]::FromBase64String($DefaultVisionPromptBase64)" in probe
assert "Invoke-RestMethod" not in probe
assert "6K+35o+P6L+w6L+Z5byg5Zu+54mH5Lit55qE5Lq654mp44CB5Yqo54mp5ZKM6IOM5pmv44CC" in probe

print("RC1.23.4 build 46 generation telemetry contracts: PASS")
