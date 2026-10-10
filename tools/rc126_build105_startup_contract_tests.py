#!/usr/bin/env python3
"""Build105 gates protect against unverified 32K KV/Batch startups."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
read=lambda n:(root/n).read_text(encoding="utf-8")
e=read("BonsaiLab/BonsaiEngine.swift");v=read("BonsaiLab/ProductionView.swift")
s=read("BonsaiLab/LocalOpenAIServer.swift");p=read("BonsaiLab/Build105StartupRecovery.swift")
w=read(".github/workflows/build-ios.yml")
assert 'CURRENT_PROJECT_VERSION: "105"' in read("project.yml")
assert 'RC126APIStartupLifecycle.begin(build: "105")' in v
assert '"build_id": "rc1.26-build105-startup-recovery"' in s
assert 'contextParams.n_seq_max = 1' in e
assert 'private let textKVReuseEnabled = false' in e
assert 'BonsaiBuild105KVCheckpointQuarantined' in e
assert 'app_build=105' in e
assert 'private var preferCertifiedB24NextLaunch = false' in v
assert 'private var textKVCheckpointEnabled104 = false' in v
assert 'Build105StartupRecovery.apply()' in v
assert 'defaults.set(false, forKey: Build94BatchExperiment.preferB24Key)' in p
assert 'migrationKey = "BonsaiBuild105RecoveryMigrationComplete"' in p
assert 'defaults.bool(forKey: Build94BatchExperiment.pendingKey)' in p
assert 'defaults.set(true, forKey: Build94BatchExperiment.fallbackKey)' in p
assert 'defaults.set(false, forKey: Build94BatchExperiment.pendingKey)' in p
assert 'defaults.set(false, forKey: Build94BatchExperiment.preferB24Key)' in p
assert '"build105_quarantined": true' in s
assert '?? maxOutputLimit' in s
assert 'gen.maxTokens = payload.maxTokens' in v
assert 'Bonsai-Build105-OneClick-FullStage.zip' in w
assert 'Build105-Safe-Startup-Recovery' in w
print("PASS Build105 quarantine seq2, one-shot safe migration, API output retained")
print("DEVICE REQUIRED: actual 32K context startup and outputs")
