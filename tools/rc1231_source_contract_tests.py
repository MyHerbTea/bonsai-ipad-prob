from pathlib import Path

root = Path(__file__).resolve().parents[1]
server = (root / "BonsaiLab" / "LocalOpenAIServer.swift").read_text()
view = (root / "BonsaiLab" / "ProductionView.swift").read_text()
engine = (root / "BonsaiLab" / "BonsaiEngine.swift").read_text()
sidecar = (root / "BonsaiLab" / "BonsaiMLXVisionSidecar.swift").read_text()
bridge = (root / "BonsaiLab" / "StagedVisionBridge.mm").read_text()

api_start = view.index("private func startAPIServer()")
api_end = view.index("private func copyAPIConfig()", api_start)
api = view[api_start:api_end]

def squash(text: str) -> str:
    return " ".join(text.split())

server_s = squash(server)
api_s = squash(api)
engine_s = squash(engine)
bridge_s = squash(bridge)

assert "OpenAIMultimodalNormalizer" in server
assert ".normalizeContent" in server
assert "OpenAIMultimodalMessageBindingValidator" in server
assert ".validate(bindingSummaries)" in server_s
assert server.count("let result = try await handler") == 2
assert 'parsed.imageCount > 0 && role != "user"' in server_s
assert "case 422: return \"Unprocessable Entity\"" in server_s
assert "selectedMLXVisionWeightsURL" in api
assert "encodeForInjection(" in api
assert "writeMLXProjectedVisionCache(" in api
assert "requireFullOutputBudget: true" in api_s
assert "prepareVisionEmbeddingCache(" not in api
assert "vision_model_unavailable" in api
assert "vision_inference_failed" in api
assert "vision_injection_failed" in api
assert "context_length_exceeded" in api
assert "cleanupAfterRequestFailure" in sidecar
assert "cleanupAfterRequestFailure" in api
assert "sharedEngine .cleanupAfterRequestFailure()" in api_s
assert "API_REQUEST_FAIL_CONTEXT_CLEARED" in engine
assert "requireFullOutputBudget: Bool = false" in engine_s
assert "TWOPHASE_B03_PREFILL_FAIL_CLEANED" in bridge
assert "packet.n_pos = static_cast<llama_pos>(" in bridge_s
assert "std::max(grid_x, grid_y)" in bridge_s

assert 'Button("刷新并复制完整诊断")' in view
assert "buildDiagnosticSnapshot()" in view
assert "BonsaiRC1231LastAPIVisionMetrics" in view
assert "=== BONSAILAB DIAGNOSTIC SNAPSHOT v1 ===" in view
assert "api_key=[REDACTED]" in view
assert "raw_image=NOT_INCLUDED" in view
assert "base64=NOT_INCLUDED" in view
assert "prompt_text=NOT_INCLUDED" in view
assert "assistant_output=NOT_INCLUDED" in view
snapshot_start = view.index("private func buildDiagnosticSnapshot()")
snapshot_end = view.index("private func startAPIServer()", snapshot_start)
snapshot_source = view[snapshot_start:snapshot_end]
assert "apiServer.apiKey" not in snapshot_source

assert "RC1232PerformanceDiagnostics" in view
assert "BonsaiRC1232LastAPIRequestMetrics" in view
assert "[LAST API REQUEST PERFORMANCE]" in view
assert "vision_encode_ms=" in view
assert "cache_write_ms=" in view
assert "prefill_ms=" in view
assert "decode_ms=" in view
assert "tokens_per_second=" in view
assert "cache_reuse=not_enabled_baseline" in view
assert "result=failed_or_interrupted" in view

print("RC1.23.1 source contracts: PASS")
