#!/usr/bin/env python3
from pathlib import Path
r=Path(__file__).resolve().parents[1]
read=lambda x:(r/x).read_text(encoding="utf-8")
engine=read("BonsaiLab/BonsaiEngine.swift")
policy=read("BonsaiLab/Build94BatchExperiment.swift")
view=read("BonsaiLab/ProductionView.swift")
server=read("BonsaiLab/LocalOpenAIServer.swift")
workflow=read(".github/workflows/build-ios.yml")
assert 'CURRENT_PROJECT_VERSION: "104"' in read("project.yml")
assert '"build_id": "rc1.26-build104-integrated-32k-performance"' in server
assert 'RC126APIStartupLifecycle.begin(build: "104")' in view
for marker in ('config.context == 32_768 && config.kvUnified &&',
               'textKVCheckpointEnabled ? 2 : 1',
               'llama_n_seq_max(context) >= 2',
               'llama_memory_seq_cp(mem, 0, 1, -1, -1)',
               'llama_memory_seq_cp(mem, 1, 0, -1, -1)',
               'llama_memory_seq_rm(mem, 0, -1, -1)',
               'llama_memory_seq_rm(mem, 1, -1, -1)',
               'checkpoint_prefix_mismatch',
               'endOffset: Int? = nil'):
    assert marker in engine,marker
assert 'post_generation_tail_trim_failed' not in engine
assert 'preferB24Key' in policy and 'certified24' in policy
assert 'preferCertifiedB24NextLaunch = true' in view
assert 'textKVCheckpointEnabled104 = true' in view
assert 'maxOutputTokens: apiMaxOutputTokens' in view
assert 'build104_text_kv_checkpoint' in server
assert 'Bonsai-Build104-OneClick-FullStage.zip' in workflow
assert 'Build104-Integrated-32K-Performance' in workflow
print("PASS: Build104 persistent B24, rollback, guarded KV seq checkpoint, API and GUI runner")
print("DEVICE REQUIRED: no speed/memory/Vision assertion from static source tests")
