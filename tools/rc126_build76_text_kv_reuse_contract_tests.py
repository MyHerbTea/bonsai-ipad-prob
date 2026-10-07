from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

engine = (ROOT / "BonsaiLab/BonsaiEngine.swift").read_text(encoding="utf-8")
server = (ROOT / "BonsaiLab/LocalOpenAIServer.swift").read_text(encoding="utf-8")
view = (ROOT / "BonsaiLab/ProductionView.swift").read_text(encoding="utf-8")
project = (ROOT / "project.yml").read_text(encoding="utf-8")
workflow = (ROOT / ".github/workflows/build-ios.yml").read_text(encoding="utf-8")

for marker in [
    "textKVResidentTokens",
    "textKVResidentContext",
    "textKVReuseEnabled = true",
    "textKVLongestCommonPrefix",
    "llama_memory_seq_rm(",
    "exact_token_lcp_tail_trim",
    "TEXT_KV_10_REUSE_",
    "TEXT_KV_11_FULL_PREFILL",
    "TEXT_KV_90_PROMPT_RETAINED",
    'reason: "api_vision_request"',
    'reason: "context_or_profile_switch"',
    'reason: "runtime_unload"',
    "tokenOffset: Int = 0",
    "startPosition: Int32 = 0",
    "struct BonsaiTextChatTurn",
    "history: [BonsaiTextChatTurn] = []",
    "for turn in history",
]:
    assert marker in engine, marker

history_block = engine[
    engine.index("for turn in history"):
    engine.index("prompt +=\n            \"<|im_start|>user\\n\"", engine.index("for turn in history"))
]
assert "let text = turn.text" in history_block
assert ".trimmingCharacters" not in history_block

for marker in [
    '"rc1.26-build76-text-kv-reuse-lab"',
    '"rc126.build76.text-kv-tail-reuse.v2"',
    '"prefix_monotonic_chatml_v1"',
    '"text_kv_reuse": textKVReuse',
    '"BonsaiRC126TextKVReuseHit"',
    '"BonsaiRC126TextKVReusedTokens"',
    "let textSystemPrompt: String",
    "let textHistory: [BonsaiTextChatTurn]",
    "var textHistory: [BonsaiTextChatTurn] = []",
    '"text_kv_reuse_implementation_id":',
    '"text_kv_reuse_prompt_format":',
    '"RC1.26_PHASE2C1_FRESH_BACKEND_VIABILITY"',
    '"rc126.phase2c1.fresh-backend-launch-latch.v1"',
]:
    assert marker in server, marker

assert "Conversation history:\\n" in server
assert 'BonsaiTextChatTurn(\n                            role: "user"' in server
assert 'BonsaiTextChatTurn(\n                            role: "assistant"' in server

for marker in [
    'RC126APIStartupLifecycle.begin(build: "76")',
    "RC1.26 Build 76 M5 Extreme Text KV Lab",
    "payload.textSystemPrompt",
    "payload.textHistory",
    "systemPrompt:",
    "apiTextSystemPrompt",
]:
    assert marker in view, marker

assert "systemPrompt:\n                                    apiSystemPrompt" in view
assert "systemPrompt:\n                                    apiTextSystemPrompt" in view
assert "history:\n                                    payload.textHistory" in view

assert 'CURRENT_PROJECT_VERSION: "76"' in project
assert "RC1.26 Build 76 Text KV reuse contracts" in workflow
assert "tools/rc126_build76_text_kv_reuse_contract_tests.py" in workflow
assert "tools/rc126_build76_text_kv_reuse_ab.ps1" in workflow
assert "RC1.26 Build 75 cold-start guard contracts" in workflow
assert "tools/rc126_build75_api_cold_start_contract_tests.py" in workflow
assert "BonsaiLab-v1-RC1.26-build76-text-kv-reuse-lab-unsigned.ipa" in workflow
assert "zip -qry ../BonsaiLab-v1-RC1.26-build75-api-cold-start-guard-unsigned.ipa Payload" not in workflow
assert "Phase2FPrefillBatchLaunchLatch.apply" in view
assert 'setenv("GGML_METAL_TENSOR_DISABLE", "1", 1)' in engine

print("RC1.26 Build 76 Text KV reuse contracts: PASS")
