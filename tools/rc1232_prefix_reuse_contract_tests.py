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
assert "TWOPHASE_B04_PREFIX_CHECKPOINT_READY" in bridge
assert "llama_memory_seq_cp" in bridge
assert "llama_memory_seq_keep" in bridge
assert "llama_memory_seq_pos_max" in bridge
assert "llama_memory_seq_rm" in bridge
assert "llama_memory_clear(mem, true)" in bridge
assert "kVisionPrefixCheckpointSeq" in bridge
assert "can_reuse_prefix ? 2u : 0u" in " ".join(bridge.split())

assert "apiVisionPrefixReuseKey" in engine
assert "apiVisionPrefixPositions" in engine
assert "enablePrefixReuse: Bool = false" in engine
assert "effectivePrefixReuse" in engine
assert "apiVisionPrefixReuseContextCapable" in engine
assert "prefixReuseContextCapable ? 2 : 1" in " ".join(engine.split())
assert "BonsaiRetainVisionPrefixKV" in engine
assert "TWOPHASE_VISION_95_PREFIX_RETAINED" in engine
assert "TWOPHASE_VISION_96_PREFIX_CHECKPOINT_UNAVAILABLE" in engine
assert "TWOPHASE_VISION_94_PREFIX_CHECKPOINT_RESTART_REQUIRED" in engine
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
