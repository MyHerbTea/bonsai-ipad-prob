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
]:
    assert marker in engine, marker

for marker in [
    '"rc1.26-build76-text-kv-reuse-lab"',
    '"RC1.26_PHASE2I_TEXT_KV_REUSE_LAB"',
    '"rc126.build76.text-kv-tail-reuse.v1"',
    '"text_kv_reuse": textKVReuse',
    '"BonsaiRC126TextKVReuseHit"',
    '"BonsaiRC126TextKVReusedTokens"',
]:
    assert marker in server, marker

for marker in [
    'RC126APIStartupLifecycle.begin(build: "76")',
    "RC1.26 Build 76 M5 Extreme Text KV Lab",
]:
    assert marker in view, marker

assert 'CURRENT_PROJECT_VERSION: "76"' in project
assert "RC1.26 Build 76 Text KV reuse contracts" in workflow
assert "tools/rc126_build76_text_kv_reuse_contract_tests.py" in workflow
assert "tools/rc126_build76_text_kv_reuse_ab.ps1" in workflow
assert "Phase2FPrefillBatchLaunchLatch.apply" in view
assert 'setenv("GGML_METAL_TENSOR_DISABLE", "1", 1)' in engine

print("RC1.26 Build 76 Text KV reuse contracts: PASS")
