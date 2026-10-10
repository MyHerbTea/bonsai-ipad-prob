"""RC1.26 Build87 scheduler context native forensics contracts."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
e=(root/"BonsaiLab/BonsaiEngine.swift").read_text()
v=(root/"BonsaiLab/ProductionView.swift").read_text()
srv=(root/"BonsaiLab/LocalOpenAIServer.swift").read_text()
flow=(root/".github/workflows/build-ios.yml").read_text()
patch=(root/"tools/rc126_build87_patch_prism_sched_context.py").read_text()
assert 'CURRENT_PROJECT_VERSION: "102"' in (root/"project.yml").read_text()
assert 'RC126APIStartupLifecycle.begin(build: "102")' in v
assert '"build_id": "rc1.26-build102-batch24-32-isolated"' in srv
assert "build87_sched_context_trace_supported" in srv
assert "build=89" in e
assert 'guard contextLength >= 32_768 else' in e
assert "复制完整原生崩溃追踪（当前及上次）" in v
assert "os_termination_cause=unknown_without_iPadOS_ips" in v
assert "BUILD87_SPLIT_CTX_FREE_BEGIN" in patch
assert "BUILD87_SPLIT_CTX_FREE_DONE" in patch
assert "BUILD87_SPLIT_GGML_INIT_BEGIN" in patch
assert "BUILD87_SPLIT_GGML_INIT_DONE" in patch
assert "BUILD87_SCHED_BUFFER_ALLOC" in patch
assert "BUILD87_SPLIT_RESET_DONE" in patch
assert "BUILD87_SPLIT_UID_DONE" in patch
assert "tools/rc126_build87_patch_prism_sched_context.py" in flow
assert "tools/rc126_build87_scheduler_context_contract_tests.py" in flow
assert "BonsaiLab-v1-RC1.26-build102-batch24-32-isolated-unsigned.ipa" in flow
assert "tools/rc126_build86_patch_prism_crash_forensics.py" in flow
assert "ctx16k-build79-validated" in v and "min(apiRuntime.gpuLayers, 56)" in v
print("RC1.26 Build87 scheduler context forensics contracts: PASS")
