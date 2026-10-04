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
assert "case eog" in types
assert "case length" in types
assert "var openAIFinishReason: String" in types

assert "let effectiveMaxTokens: Int" in metrics
assert "let terminationReason: GenerationTerminationReason" in metrics

assert len(re.findall(r"terminationReason:\s*generated\.terminationReason", engine)) >= 3
assert "var terminationReason: GenerationTerminationReason = .length" in engine
assert "terminationReason = .eog" in engine
assert engine.count("effectiveMaxTokens:") >= 3

assert view.count("requestedMaxTokens: Int") >= 2
assert view.count("requestedMaxTokens: payload.maxTokens") >= 2
assert "requested_max_tokens=" in view
assert "effective_max_tokens=" in view
assert "termination_reason=" in view
assert "finish_reason=" in view

assert "metrics.generation.terminationReason.openAIFinishReason" in view
assert "metrics.terminationReason.openAIFinishReason" in view
assert "generatedTokens\n                                >= gen.maxTokens" not in view

assert 'CURRENT_PROJECT_VERSION: "46"' in project
print("RC1.23.4 build 46 generation telemetry contracts: PASS")
