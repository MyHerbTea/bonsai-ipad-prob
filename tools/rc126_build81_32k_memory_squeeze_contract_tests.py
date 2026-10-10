from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
view = (ROOT / "BonsaiLab/ProductionView.swift").read_text(encoding="utf-8")
engine = (ROOT / "BonsaiLab/BonsaiEngine.swift").read_text(encoding="utf-8")
server = (ROOT / "BonsaiLab/LocalOpenAIServer.swift").read_text(encoding="utf-8")
project = (ROOT / "project.yml").read_text(encoding="utf-8")
workflow = (ROOT / ".github/workflows/build-ios.yml").read_text(encoding="utf-8")

assert ('CURRENT_PROJECT_VERSION: "81"' in project or 'CURRENT_PROJECT_VERSION: "82"' in project
    or 'CURRENT_PROJECT_VERSION: "104"' in project)
assert ('RC126APIStartupLifecycle.begin(build: "81")' in view or 'RC126APIStartupLifecycle.begin(build: "82")' in view
    or 'RC126APIStartupLifecycle.begin(build: "104")' in view)
assert ("RC1.26 Build 81 32K Memory Squeeze" in view or "RC1.26 Build 82 Unified-Metal 32K Lab" in view
    or "RC1.26 Build 89 Compact Scheduler Metadata" in view)
assert ('"build_id": "rc1.26-build81-32k-memory-squeeze"' in server or '"build_id": "rc1.26-build82-unified-metal-32k-lab"' in server
    or '"build_id": "rc1.26-build104-integrated-32k-performance"' in server)
assert "private func applyBuild82LongContextPolicy(" in view
assert view.count("applyBuild82LongContextPolicy(") == 3

assert "ctx16k-build79-validated" in view
assert "min(apiRuntime.gpuLayers, 56)" in view
assert ("ctx32k-q4-gpu24-b4-cpu-kqv-op" in view or "ctx32k-q4-unified-metal-gpu99-b4" in view)
assert "apiRuntime.batch = min(apiRuntime.batch, batchCap)" in view and "case .candidate16: batchCap = 16" in view
assert "apiRuntime.ubatch = min(apiRuntime.ubatch, batchCap)" in view and "case .candidate16: batchCap = 16" in view
assert ("min(apiRuntime.gpuLayers, 24)" in view or "ctx32k-q4-unified-metal-gpu99-b4" in view)
assert ("ctx64k-q4-gpu8-b2-cpu-kqv-op" in view or "ctx64k-q4-unified-metal-gpu99-b2" in view)
assert "min(apiRuntime.batch, 2)" in view
assert "min(apiRuntime.ubatch, 2)" in view
assert ("min(apiRuntime.gpuLayers, 8)" in view or "ctx64k-q4-unified-metal-gpu99-b2" in view)

policy_start = view.index("private func applyBuild82LongContextPolicy(")
policy_end = view.index("private func reconfigureAPIRuntimePreservingModel()", policy_start)
policy = view[policy_start:policy_end]
if "ctx32k-q4-unified-metal-gpu99-b4" in view:
    assert policy.count("apiRuntime.offloadKQV = true") >= 2
    assert policy.count("apiRuntime.opOffload = true") >= 2
else:
    assert policy.count("apiRuntime.offloadKQV = false") == 2
    assert policy.count("apiRuntime.opOffload = false") == 2

assert "build81ThreadCap = 4" in engine
assert "build81ThreadCap = 2" in engine
assert "BonsaiBuild81ContextCreateAttempt" in engine
assert "BonsaiBuild81ContextCreateCompleted" in engine

for field in [
    "build81_squeeze_profile",
    "build81_effective_batch",
    "build81_effective_ubatch",
    "build81_effective_gpu_layers",
    "build81_offload_kqv",
    "build81_op_offload",
    "build81_effective_threads",
    "build81_context_create_attempt",
    "build81_context_create_completed",
]:
    assert field in server, field

assert "RC1.26 Build 81 32K memory squeeze contracts" in workflow
assert "tools/rc126_build81_32k_memory_squeeze_contract_tests.py" in workflow
assert ("BonsaiLab-v1-RC1.26-build81-32k-memory-squeeze-unsigned.ipa" in workflow or "BonsaiLab-v1-RC1.26-build82-unified-metal-32k-lab-unsigned.ipa" in workflow
    or "BonsaiLab-v1-RC1.26-build104-integrated-32k-performance-unsigned.ipa" in workflow)
assert ("BonsaiLab-iPad-v1-RC1.26-Build81-32K-Memory-Squeeze" in workflow or "BonsaiLab-iPad-v1-RC1.26-Build82-Unified-Metal-32K-Lab" in workflow
    or "BonsaiLab-iPad-v1-RC1.26-Build104-Integrated-32K-Performance" in workflow)
print("RC1.26 Build 81 32K memory squeeze contracts: PASS")
