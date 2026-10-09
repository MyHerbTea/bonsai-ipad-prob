from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
view = (ROOT / "BonsaiLab/ProductionView.swift").read_text(encoding="utf-8")
server = (ROOT / "BonsaiLab/LocalOpenAIServer.swift").read_text(encoding="utf-8")
project = (ROOT / "project.yml").read_text(encoding="utf-8")
workflow = (ROOT / ".github/workflows/build-ios.yml").read_text(encoding="utf-8")
patcher = (ROOT / "tools/rc126_build83_patch_prism_kv_sharding.py").read_text(encoding="utf-8")

assert ('CURRENT_PROJECT_VERSION: "94"' in project or 'CURRENT_PROJECT_VERSION: "95"' in project)
assert ('RC126APIStartupLifecycle.begin(build: "94"' in view or 'RC126APIStartupLifecycle.begin(build: "95"' in view)
assert "RC1.26 Build 89 Compact Scheduler Metadata" in view
assert ('"build_id": "rc1.26-build94-prefill-kernel-boundary-p0"' in server or '"build_id": "rc1.26-build95-native-k1-ptq1-dense5"' in server)

assert "ctx32k-q4-unified-metal-gpu99-b4" in view
assert "apiRuntime.gpuLayers = 99" in view
assert "apiRuntime.batch = min(apiRuntime.batch, batchCap)" in view and "case .candidate16: batchCap = 16" in view
assert "apiRuntime.ubatch = min(apiRuntime.ubatch, batchCap)" in view and "case .candidate16: batchCap = 16" in view
assert "apiRuntime.offloadKQV = true" in view
assert "apiRuntime.opOffload = true" in view

for marker in [
    "BUILD83_METAL_KV_LAYER_SHARD",
    "build83_ctx_key",
    "kv_size >= 32768",
    "LLM_ARCH_QWEN35",
    "LLM_ARCH_QWEN35MOE",
    'strncmp(dev_name, "MTL", 3) == 0',
]:
    assert marker in patcher, marker

assert "expected exactly once" in patcher
assert "Build83 patch refused" in patcher
assert "[BUILD 83 EFFECTIVE LONG CONTEXT]" in view
assert "prism_metal_kv_layer_sharding=true" in view
assert '"build83_prism_kv_layer_sharding": true' in server

assert "git clone --filter=blob:none https://github.com/PrismML-Eng/llama.cpp.git" in workflow
assert "adfffbe41b2cabcd51fff326ab045662265062bb" in workflow
assert "rc126_build83_patch_prism_kv_sharding.py" in workflow
assert "build-xcframework.sh ios-device" in workflow
assert "RC1.26 Build 83 Prism Metal KV sharding contracts" in workflow
assert ("BonsaiLab-v1-RC1.26-build94-prefill-kernel-boundary-p0-unsigned.ipa" in workflow or "BonsaiLab-v1-RC1.26-build95-native-k1-ptq1-dense5-unsigned.ipa" in workflow)
assert ("BonsaiLab-iPad-v1-RC1.26-Build94-Prefill-Kernel-Boundary-P0" in workflow or "BonsaiLab-iPad-v1-RC1.26-Build95-Native-K1-PTQ1-Dense5" in workflow)

print("RC1.26 Build 83 Prism Metal KV sharding contracts: PASS")
