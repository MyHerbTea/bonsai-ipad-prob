from pathlib import Path

root = Path(__file__).resolve().parents[1]
view = (root / "BonsaiLab" / "ProductionView.swift").read_text()
engine = (root / "BonsaiLab" / "BonsaiEngine.swift").read_text()

# RC1.23.3 Phase A is observability only.
assert "BonsaiRC1233LongRunRequestHistory" in view
assert "beginSession()" in view
assert "beginRequest()" in view
assert "ProcessInfo.processInfo.thermalState" in view
assert "isLowPowerModeEnabled" in view
assert "request_ordinal=" in view
assert "[RC1.23.3 LONG-RUN REQUEST HISTORY]" in view
assert "historyLimit = 32" in view
assert "apiAdmissionSnapshot()" in view

for field in [
    "available_mib=",
    "resident_mib=",
    "phys_footprint_mib=",
    "virtual_mib=",
    "metal_allocated_mib=",
    "metal_recommended_mib=",
    "prefill_ms=",
    "suffix_prefill_ms=",
    "decode_ms=",
    "tokens_per_second=",
    "vision_encode_ms=",
    "idle_gap_ms=",
    "session_elapsed_start_ms=",
    "session_elapsed_end_ms=",
    "thermal_state_start=",
    "thermal_state_end=",
    "low_power_mode_start=",
    "low_power_mode_end=",
]:
    assert field in view

# A2 thermal/idle-gap correlation is observational only.
assert "thermal_start=" in view
assert "thermal_end=" in view
assert "session_elapsed_ms=" in view

# Privacy boundary remains explicit.
assert "api_key=[REDACTED]" in view
assert "raw_image=NOT_INCLUDED" in view
assert "base64=NOT_INCLUDED" in view
assert "prompt_text=NOT_INCLUDED" in view
assert "assistant_output=NOT_INCLUDED" in view

# Frozen C2-B invariants remain untouched.
assert "contextParams.n_seq_max =" in engine and "config.context == 32_768 && textKVCheckpointEnabled ? 2 : 1" in engine
assert "params.n_seq_max = 1" in engine
assert "apiVisionPrefixReuseKey" in engine
assert "BonsaiRetainVisionPrefixKV" in engine
assert "apiVisionPrefixReuseContextCapable" not in engine
assert "TWOPHASE_VISION_94_PREFIX_CHECKPOINT_RESTART_REQUIRED" not in engine

print("RC1.23.3 long-run + thermal observability contracts: PASS")
