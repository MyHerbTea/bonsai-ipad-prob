from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
engine = (ROOT / "BonsaiLab/BonsaiEngine.swift").read_text(encoding="utf-8")
bridge_h = (ROOT / "BonsaiLab/MTMDProbeBridge.h").read_text(encoding="utf-8")
bridge_mm = (ROOT / "BonsaiLab/MTMDProbeBridge.mm").read_text(encoding="utf-8")
view = (ROOT / "BonsaiLab/ProductionView.swift").read_text(encoding="utf-8")
server = (ROOT / "BonsaiLab/LocalOpenAIServer.swift").read_text(encoding="utf-8")
types = (ROOT / "BonsaiLab/LabTypes.swift").read_text(encoding="utf-8")
project = (ROOT / "project.yml").read_text(encoding="utf-8")
workflow = (ROOT / ".github/workflows/build-ios.yml").read_text(encoding="utf-8")
ent = (ROOT / "BonsaiLab/BonsaiLab.entitlements").read_text(encoding="utf-8")

assert "context <= 65_536" in types
assert "256...65536" in types

for value in ["4096", "6144", "8192", "16384", "32768", "65536"]:
    assert f'.tag("{value}")' in view, value

assert "Q8 KV" in view
assert "Q4 KV" in view
assert "min(apiRuntime.gpuLayers, 56)" in view
assert ("min(apiRuntime.gpuLayers, 40)" in view or "ctx32k-q4-gpu24-b4-cpu-kqv-op" in view or "ctx32k-q4-unified-metal-gpu99-b4" in view)
assert (
    "min(apiRuntime.gpuLayers, 24)" in view
    or "ctx64k-q4-unified-metal-gpu99-b2" in view
)
assert "apiRuntime.batch = min(apiRuntime.batch, batchCap)" in view and "case .candidate16: batchCap = 16" in view
assert "apiRuntime.flashAttention = true" in view
assert 'apiRuntime.loadMode = .mmap' in view

for marker in [
    "GGML_TYPE_Q8_0",
    "GGML_TYPE_Q4_0",
    "BonsaiBuild79KVCacheType",
    "BonsaiBuild79BeforeModelMmap",
    "BonsaiBuild79AfterModelMmap",
    "BonsaiBuild79BeforeContextCreate",
    "BonsaiBuild79AfterContextCreate",
    "llama_model_n_ctx_train",
    "BonsaiEffectiveEntitlementFlag",
    "MetalAllocatedMiB",
    "MetalRecommendedMiB",
]:
    assert marker in engine, marker

assert "import Security" not in engine
assert "BonsaiEffectiveEntitlementFlag" in bridge_h
assert 'dlsym(RTLD_DEFAULT, "SecTaskCreateFromSelf")' in bridge_mm
assert 'dlsym(RTLD_DEFAULT, "SecTaskCopyValueForEntitlement")' in bridge_mm
assert (
    'CURRENT_PROJECT_VERSION: "79"' in project
    or 'CURRENT_PROJECT_VERSION: "80"' in project
    or 'CURRENT_PROJECT_VERSION: "81"' in project
    or 'CURRENT_PROJECT_VERSION: "82"' in project
    or 'CURRENT_PROJECT_VERSION: "94"' in project
    or 'CURRENT_PROJECT_VERSION: "96"' in project
)
assert 'CODE_SIGN_ENTITLEMENTS: "BonsaiLab/BonsaiLab.entitlements"' in project
assert "Security.framework" in project
assert "com.apple.developer.kernel.extended-virtual-addressing" in ent
assert "com.apple.developer.kernel.increased-memory-limit" in ent
assert (
    '"build_id": "rc1.26-build79-storage-memory-long-context-lab"' in server
    or '"build_id": "rc1.26-build80-long-context-tier-reload-fix"' in server
    or '"build_id": "rc1.26-build81-32k-memory-squeeze"' in server
    or '"build_id": "rc1.26-build82-unified-metal-32k-lab"' in server
    or '"build_id": "rc1.26-build94-prefill-kernel-boundary-p0"' in server
    or '"build_id": "rc1.26-build96-native-k2-gdn-simd"' in server
)
assert "build79_kv_cache_type" in server
assert "build79_effective_extended_va" in server
assert "build79_effective_increased_memory_limit" in server
assert (
    'RC126APIStartupLifecycle.begin(build: "79")' in view
    or 'RC126APIStartupLifecycle.begin(build: "80")' in view
    or 'RC126APIStartupLifecycle.begin(build: "81")' in view
    or 'RC126APIStartupLifecycle.begin(build: "82")' in view
    or 'RC126APIStartupLifecycle.begin(build: "94")' in view
    or 'RC126APIStartupLifecycle.begin(build: "96")' in view
)
assert (
    "RC1.26 Build 79 Storage-Memory Long Context Lab" in view
    or "RC1.26 Build 80 Long-Context Tier Reload Fix" in view
    or "RC1.26 Build 81 32K Memory Squeeze" in view
    or "RC1.26 Build 82 Unified-Metal 32K Lab" in view
    or "RC1.26 Build 89 Compact Scheduler Metadata" in view
)
assert "RC1.26 Build 79 storage-memory long-context contracts" in workflow
assert "tools/rc126_build79_storage_memory_contract_tests.py" in workflow

package_marker = "\n      - name: Package unsigned IPA\n"
upload_marker = "\n      - name: Upload artifact\n"
package_start = workflow.index(package_marker)
upload_start = workflow.index(upload_marker, package_start)
package_block = workflow[package_start:upload_start]
assert (
    "BonsaiLab-v1-RC1.26-build79-storage-memory-long-context-lab-unsigned.ipa" in package_block
    or "BonsaiLab-v1-RC1.26-build80-long-context-tier-reload-fix-unsigned.ipa" in package_block
    or "BonsaiLab-v1-RC1.26-build81-32k-memory-squeeze-unsigned.ipa" in package_block
    or "BonsaiLab-v1-RC1.26-build82-unified-metal-32k-lab-unsigned.ipa" in package_block
    or "BonsaiLab-v1-RC1.26-build94-prefill-kernel-boundary-p0-unsigned.ipa" in package_block
    or "BonsaiLab-v1-RC1.26-build96-native-k2-gdn-simd-unsigned.ipa" in package_block
)
assert "build78-context-boundary-lab-unsigned.ipa" not in package_block

print("RC1.26 Build 79 storage-memory long-context contracts: PASS")
