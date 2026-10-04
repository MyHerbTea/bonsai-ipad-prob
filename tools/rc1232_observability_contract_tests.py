from pathlib import Path

root = Path(__file__).resolve().parents[1]
view = (root / "BonsaiLab" / "ProductionView.swift").read_text()

assert "RC1232PerformanceDiagnostics" in view
assert "BonsaiRC1232LastAPIRequestMetrics" in view
assert "[LAST API REQUEST PERFORMANCE]" in view
assert "request_id=" in view
assert "route=vision" in view
assert "route=text" in view
assert "vision_encode_ms=" in view
assert "vision_encode_reported_ms=" in view
assert "cache_write_ms=" in view
assert "prefill_ms=" in view
assert "ttft_ms=" in view
assert "decode_ms=" in view
assert "tokens_per_second=" in view
assert "prompt_tokens=" in view
assert "completion_tokens=" in view
assert "visual_rows=" in view
assert "projection_dim=" in view
assert "grid=" in view
assert "n_pos=" in view
assert "image_ordering=" in view
assert "cache_reuse=" in view
assert "result=failed_or_interrupted" in view
assert "api_key=[REDACTED]" in view
assert "base64=NOT_INCLUDED" in view

print("RC1.23.2 observability contracts: PASS")
