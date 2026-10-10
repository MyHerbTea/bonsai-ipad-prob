#!/usr/bin/env python3
"""Build99 offline safety contracts. Not a replacement for real model/GPU tests."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
engine = (root / "BonsaiLab/BonsaiEngine.swift").read_text(encoding="utf-8")
ui = (root / "BonsaiLab/ProductionView.swift").read_text(encoding="utf-8")
app = (root / "BonsaiLab/BonsaiLabApp.swift").read_text(encoding="utf-8")
latch = (root / "BonsaiLab/Build99AppendOnlyReuse.swift").read_text(encoding="utf-8")
api = (root / "BonsaiLab/LocalOpenAIServer.swift").read_text(encoding="utf-8")

def require(value, source, purpose):
    assert value in source, "MISSING contract %s: %s" % (purpose, value)

require('private let textKVAppendOnlyEnabled = Build99AppendOnlyReuse.enabled', engine, "process latch")
require('if textKVAppendOnlyEnabled {', engine, "gated candidate")
require('tokens.count > textKVResidentTokens.count', engine, "suffix must exist")
require('tokens.starts(with: textKVResidentTokens)', engine, "exact token prefix")
require('textKVResidentTokens.count >= textKVMinimumReuseTokens', engine, "minimum reuse")
require('reuseReason = "append_only_exact_extension"', engine, "success telemetry")
require('reuseReason = "append_only_no_exact_extension"', engine, "cold fallback telemetry")
require('startPosition: Int32(reusedTokens)', engine, "physical token positions")
require('textKVResidentTokens = tokens + generated.tokenIDs', engine, "complete state ledger")
require('generated.tokenIDs.count == generated.count', engine, "token recording completeness")
require('generatedTokenIDs.append(token)', engine, "actual successfully decoded tokens")
require('if stagePrefix == "TEXT"', engine, "do not record vision token ids")
require('llama_memory_clear(', engine, "frozen safe reset")
require('let retainedPrompt =', engine, "Build97 path preserved")
require('llama_memory_seq_rm(', engine, "original rollback fallback untouched")
require('clearTextKVReuseState(reason: "append_only_incomplete_ledger")', engine, "candidate fail closed")
require('catch {\n            clearTextKVReuseState(', engine, "text failures clear state")
require('defaults.set("OFF", forKey: nextKey)', latch, "automatic next-launch recovery")
require('let arm = next == "APPEND" ? "APPEND" : "OFF"', latch, "invalid arm fails closed")
require('Build99AppendOnlyReuse.activeArm', app, "latch initialized before view")
require('Text("OFF · 原始安全路径")', ui, "local opt-in")
require('Text("APPEND · 精确前缀续算")', ui, "candidate selector")
require('"build99_append_only": Build99AppendOnlyReuse.snapshot()', api, "read-only observer")

start = engine.index("            // Build99 candidate: use only an exact extension")
end = engine.index("            } else if textKVReuseEnabled,", start)
candidate = engine[start:end]
assert "llama_memory_seq_rm" not in candidate, "candidate must never attempt GDN rollback"
assert "llama_memory_clear" not in candidate, "candidate must only append when exact"

def match(old, new, threshold=16):
    return len(old) >= threshold and len(new) > len(old) and new[:len(old)] == old

old = list(range(24))
assert match(old, old + [24, 25]), "exact extension should reuse"
assert not match(old, old), "equal prompt needs logits; full prefill"
assert not match(old, old[:18]), "truncated history must be cold"
assert not match(old, old[:23] + [99, 100]), "divergence must be cold"
assert not match(old[:10], old), "short state should be cold"
assert not match(old, [999] + old), "new system prompt must be cold"

print("PASS Build99 source and conservative append-only token-ledger contracts")
print("NOTE: Real GGUF tokenizer, ChatML exact prefix, and iPad GPU numerical equivalence are NOT verified by this test.")
