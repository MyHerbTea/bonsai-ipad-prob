from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
types = (root / "BonsaiLab" / "LabTypes.swift").read_text()
engine = (root / "BonsaiLab" / "BonsaiEngine.swift").read_text()
view = (root / "BonsaiLab" / "ProductionView.swift").read_text()
project = (root / "project.yml").read_text()

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

assert re.search(
    r'CURRENT_PROJECT_VERSION:\s*"46"',
    project,
)

print("RC1.23.4 build 46 generation telemetry contracts: PASS")
