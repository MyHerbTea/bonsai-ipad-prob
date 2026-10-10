#!/usr/bin/env python3
"""Structural integration invariants; real Swift lifecycle behavior is tested separately."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
view = (root / "BonsaiLab/ProductionView.swift").read_text()
engine = (root / "BonsaiLab/BonsaiEngine.swift").read_text()
server = (root / "BonsaiLab/LocalOpenAIServer.swift").read_text()
policy = (root / "BonsaiLab/Build93BatchTrialPolicy.swift").read_text()
project = (root / "project.yml").read_text()
assert 'CURRENT_PROJECT_VERSION: "100"' in project
assert 'RC126APIStartupLifecycle.begin(build: "100")' in view
assert '"build_id": "rc1.26-build100-b16-accel-guarded"' in server
assert '"schema": "bonsai-build94-execution-v1"' in server
assert 'Build94BatchExperiment.select(context: context)' in view
assert 'case .candidate16: batchCap = 16' in view
assert 'apiRuntime.batch = min(apiRuntime.batch, batchCap)' in view
assert 'apiRuntime.ubatch = min(apiRuntime.ubatch, batchCap)' in view
assert 'Build94BatchExperiment.noteTextSuccess(' in view
assert 'Build94BatchExperiment.noteStartupFailure()' in view
assert view.index('Phase2FPrefillBatchLaunchLatch.apply(') < view.index('applyBuild82LongContextPolicy(', view.index('private func startAPIServer()'))
assert 'contextParams.n_batch = UInt32(config.batch)' in engine
assert 'contextParams.n_ubatch = UInt32(config.ubatch)' in engine
assert 'batchSize:\n                        appliedRuntime.batch' in engine
assert 'onProgress?("decode_begin"' in engine
assert 'onProgress?("decode_end"' in engine
for field in ['"batch_trial"', '"engine_context_batch"', '"engine_context_ubatch"', '"pending"', '"sticky_fallback"']:
    assert field in server
for field in ['pendingKey', 'fallbackKey', 'confirmedKey', 'reasonKey', 'modeKey']:
    assert field in policy
print("Build93 integration source contract: PASS (behavior checked by Swift executable test)")
