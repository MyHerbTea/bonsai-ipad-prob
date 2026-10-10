"""Build88 experimental scheduler mmap recovery + baseline-safety static contracts."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
engine = (root/"BonsaiLab/BonsaiEngine.swift").read_text(encoding="utf-8")
view = (root/"BonsaiLab/ProductionView.swift").read_text(encoding="utf-8")
server = (root/"BonsaiLab/LocalOpenAIServer.swift").read_text(encoding="utf-8")
workflow = (root/".github/workflows/build-ios.yml").read_text(encoding="utf-8")
patch = (root/"tools/rc126_build88_patch_prism_mmap_recovery.py").read_text(encoding="utf-8")
assert 'CURRENT_PROJECT_VERSION: "99"' in (root/"project.yml").read_text()
assert 'RC126APIStartupLifecycle.begin(build: "99"' in view
assert '"build_id": "rc1.26-build99-append-only-prefix-speed-lab"' in server
assert '"build88_scheduler_mmap_recovery": true' in server
assert "build=89" in engine
assert "ctx16k-build79-validated" in view
assert "min(apiRuntime.gpuLayers, 56)" in view
assert 'guard contextLength >= 32_768 else' in engine
assert "BONSAI_BUILD84_TRACE_PATH" in patch
assert "MAP_PRIVATE | MAP_ANON" in patch
assert 'if (sched->context_buffer == NULL && getenv("BONSAI_BUILD84_TRACE_PATH") != NULL)' in patch
assert "BUILD88_MMAP_BEGIN" in patch and "BUILD88_MMAP_SUCCESS" in patch
assert "BUILD88_MMAP_FAILURE" in patch and "BUILD88_SCHED_ALLOC_EXHAUSTED" in patch
assert "context_buffer_mmap = true" in patch and "munmap(sched->context_buffer, sched->context_buffer_size)" in patch
assert "BUILD88_SCHED_NEW_NULL_CTX_ABORT_PREVENTED" in patch
assert "throw std::runtime_error" in patch
assert "tools/rc126_build88_patch_prism_mmap_recovery.py" in workflow
assert "tools/rc126_build88_scheduler_mmap_contract_tests.py" in workflow
assert "BonsaiLab-v1-RC1.26-build99-append-only-prefix-speed-lab-unsigned.ipa" in workflow
print("RC1.26 Build88 scheduler mmap recovery contracts: PASS")
