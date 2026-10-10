from pathlib import Path
root=Path(__file__).resolve().parents[1]
e=(root/"BonsaiLab/BonsaiEngine.swift").read_text()
v=(root/"BonsaiLab/ProductionView.swift").read_text()
srv=(root/"BonsaiLab/LocalOpenAIServer.swift").read_text()
wf=(root/".github/workflows/build-ios.yml").read_text()
p=(root/"tools/rc126_build89_patch_prism_compact_scheduler.py").read_text()
assert 'CURRENT_PROJECT_VERSION: "98"' in (root/"project.yml").read_text()
assert 'RC126APIStartupLifecycle.begin(build: "97"' in v
assert '"build_id": "rc1.26-build98-m5-fa-vec-ab"' in srv
assert '"build89_compact_scheduler_metadata": true' in srv
assert 'let header = "build=89' in e
assert 'guard contextLength >= 32_768 else' in e
assert "ctx16k-build79-validated" in v and "min(apiRuntime.gpuLayers, 56)" in v
assert 'BONSAI_BUILD84_TRACE_PATH' in p
assert 'sched->context_buffer == NULL' in p
assert 'sched->hash_set.size' in p and 'sched->n_backends' in p and 'sched->n_copies' in p
assert 'ggml_tensor_overhead()' in p and 'ggml_graph_overhead_custom' in p
assert 'BUILD89_COMPACT_BUDGET' in p and 'BUILD89_COMPACT_ALLOC_SUCCESS' in p
assert 'BUILD89_COMPACT_ALLOC_FAILURE' in p and 'BUILD89_META_USED' in p
assert 'ggml_used_mem(sched->ctx)' in p
assert 'rc126_build88_patch_prism_mmap_recovery.py' in wf
assert 'rc126_build89_patch_prism_compact_scheduler.py' in wf
assert 'BonsaiLab-v1-RC1.26-build98-m5-fa-vec-ab-unsigned.ipa' in wf
print("RC1.26 Build89 bounded scheduler metadata contracts: PASS")
