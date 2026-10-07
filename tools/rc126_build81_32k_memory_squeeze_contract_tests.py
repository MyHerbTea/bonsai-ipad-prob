from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
view = (ROOT / "BonsaiLab/ProductionView.swift").read_text(encoding="utf-8")
engine = (ROOT / "BonsaiLab/BonsaiEngine.swift").read_text(encoding="utf-8")
server = (ROOT / "BonsaiLab/LocalOpenAIServer.swift").read_text(encoding="utf-8")
project = (ROOT / "project.yml").read_text(encoding="utf-8")
workflow = (ROOT / ".github/workflows/build-ios.yml").read_text(encoding="utf-8")

assert 'CURRENT_PROJECT_VERSION: "81"' in project
assert 'RC126APIStartupLifecycle.begin(build: "81")' in view
assert "RC1.26 Build 81 32K Memory Squeeze" in view
assert '"build_id": "rc1.26-build81-32k-memory-squeeze"' in server
assert "private func applyBuild81LongContextPolicy(" in view
assert view.count("applyBuild81LongContextPolicy(") == 3

assert "ctx16k-build79-validated" in view
assert "min(apiRuntime.gpuLayers, 56)" in view
assert "ctx32k-q4-gpu24-b4-cpu-kqv-op" in view
assert "min(apiRuntime.batch, 4)" in view
assert "min(apiRuntime.ubatch, 4)" in view
assert "min(apiRuntime.gpuLayers, 24)" in view
assert "ctx64k-q4-gpu8-b2-cpu-kqv-op" in view
assert "min(apiRuntime.batch, 2)" in view
assert "min(apiRuntime.ubatch, 2)" in view
assert "min(apiRuntime.gpuLayers, 8)" in view

policy_start = view.index("private func applyBuild81LongContextPolicy(")
policy_end = view.index("private func reconfigureAPIRuntimePreservingModel()", policy_start)
policy = view[policy_start:policy_end]
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
assert "BonsaiLab-v1-RC1.26-build81-32k-memory-squeeze-unsigned.ipa" in workflow
assert "BonsaiLab-iPad-v1-RC1.26-Build81-32K-Memory-Squeeze" in workflow
print("RC1.26 Build 81 32K memory squeeze contracts: PASS")
