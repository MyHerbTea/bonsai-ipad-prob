from pathlib import Path

root = Path(__file__).resolve().parents[1]
header = (root / "BonsaiLab" / "StagedVisionBridge.h").read_text()
bridge = (root / "BonsaiLab" / "StagedVisionBridge.mm").read_text()
engine = (root / "BonsaiLab" / "BonsaiEngine.swift").read_text()

# Native bridge receives the actual runtime context and requested completion
# budget so it can reject before llama_decode.
assert "int32_t context_limit" in header
assert "int32_t requested_max_tokens" in header
assert "int32_t context_limit" in bridge
assert "int32_t requested_max_tokens" in bridge

bridge_func = bridge[
    bridge.index("BonsaiVisionPrefillResult BonsaiPrefillCachedVision("):
]

admission = bridge_func.index("const llama_pos planned_input_positions")
prefill_loop = bridge_func.index(
    "for (size_t i = begin_index; i < packet.size(); ++i)"
)
decode_call = bridge_func.index("decode_text_chunk(", prefill_loop)
assert admission < prefill_loop < decode_call

for marker in [
    "planned_input_positions",
    "positional_required_context",
    "planned_prompt_kv_tokens",
    "kv_required_context",
    "requested_max_tokens",
    "context_limit",
    "TWOPHASE_B02_CONTEXT_BUDGET_REJECTED",
    "result.code = 9",
]:
    assert marker in bridge_func

assert "positional_required_context > context_limit" in bridge_func
assert "planned_prompt_kv_tokens >= context_limit" in bridge_func
assert "kv_required_context > context_limit" in bridge_func

# Rejection must happen before memory-clear/reuse/decode mutation in the
# cached-vision prefill function itself.
rejection = bridge_func.index("TWOPHASE_B02_CONTEXT_BUDGET_REJECTED")
memory_lookup = bridge_func.index("llama_memory_t mem = llama_get_memory(ctx)")
assert rejection < memory_lookup

# Swift passes the exact values and translates native admission code 9 back
# into the structured API budget error instead of a generic 500.
assert "Int32(appliedRuntime.context)" in engine
assert "Int32(requireFullOutputBudget ? gen.maxTokens : 1)" in engine
assert "min(\n                    gen.maxTokens,\n                    available" in engine
assert "if prefill.code == 9" in engine
assert "LabError.contextBudgetExceeded(" in engine

print("RC1.25.1 Build 60 dual context admission contracts: PASS")
