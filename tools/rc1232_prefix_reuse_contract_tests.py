from pathlib import Path

root = Path(__file__).resolve().parents[1]
header = (root / "BonsaiLab" / "StagedVisionBridge.h").read_text()
bridge = (root / "BonsaiLab" / "StagedVisionBridge.mm").read_text()
engine = (root / "BonsaiLab" / "BonsaiEngine.swift").read_text()
view = (root / "BonsaiLab" / "ProductionView.swift").read_text()
types = (root / "BonsaiLab" / "LabTypes.swift").read_text()

assert "prefix_positions" in header
assert "prefix_reuse_hit" in header
assert "prefix_text_ms" in header
assert "image_prefill_ms" in header
assert "suffix_prefill_ms" in header
assert "reuse_prefix" in header
assert "expected_prefix_positions" in header
assert "BonsaiRetainVisionPrefixKV" in header

assert "TWOPHASE_B03_PREFIX_REUSE_HIT" in bridge
assert "TWOPHASE_B03_PREFIX_REUSE_MISS" in bridge
assert "TWOPHASE_B04_PREFIX_STATE_READY" in bridge
assert "TWOPHASE_B04_PREFIX_STATE_UNAVAILABLE" in bridge
assert "llama_state_seq_get_size_ext" in bridge
assert "llama_state_seq_get_data_ext" in bridge
assert "llama_state_seq_set_data_ext" in bridge
assert "LLAMA_STATE_SEQ_FLAGS_ON_DEVICE" in bridge
assert "save_vision_prefix_state_locked" in bridge
assert "restore_vision_prefix_state_locked" in bridge
assert "llama_memory_clear(mem, true)" in bridge
assert "kVisionPrefixCheckpointSeq" not in bridge
assert "llama_memory_seq_cp" not in bridge
assert "llama_memory_seq_keep" not in bridge
assert "can_reuse_prefix ? 2u : 0u" in " ".join(bridge.split())

assert "apiVisionPrefixReuseKey" in engine
assert "apiVisionPrefixPositions" in engine
assert "enablePrefixReuse: Bool = false" in engine
assert "effectivePrefixReuse" in engine
assert "apiVisionPrefixReuseContextCapable" not in engine
assert "prefixReuseContextCapable ? 2 : 1" not in " ".join(engine.split())
assert "contextParams.n_seq_max = 1" in engine, "Build104 only adds seq1 for unified text KV; legacy Vision stays seq1"
assert "params.n_seq_max = 1" in engine
assert "BonsaiRetainVisionPrefixKV" in engine
assert "TWOPHASE_VISION_95_PREFIX_RETAINED" in engine
assert "TWOPHASE_VISION_96_PREFIX_CHECKPOINT_UNAVAILABLE" in engine
assert "TWOPHASE_VISION_94_PREFIX_CHECKPOINT_RESTART_REQUIRED" not in engine
assert "apiVisionPrefixReuseKey = nil" in engine

assert "prefixReuseHit" in types
assert "prefixRetainedForReuse" in types

assert "BonsaiRC1232VisionPrefixKVReuseEnabled" in view
assert "实验：Vision Prefix KV Reuse" in view
assert "prefix_reuse_enabled=" in view
assert "prefix_reuse_hit=" in view
assert "prefix_retained=" in view
assert "prefix_text_ms=" in view
assert "image_prefill_ms=" in view
assert "suffix_prefill_ms=" in view
assert "vision_prefix_kv_reuse_enabled=" in view

print("RC1.23.2 prefix KV reuse contracts: PASS")
