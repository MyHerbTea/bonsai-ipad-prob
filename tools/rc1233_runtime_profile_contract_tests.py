from pathlib import Path

root = Path(__file__).resolve().parents[1]
view = (root / "BonsaiLab" / "ProductionView.swift").read_text()
project = (root / "project.yml").read_text()
engine = (root / "BonsaiLab" / "BonsaiEngine.swift").read_text()

# Build 44 keeps the proven safe runtime as the persisted default.
assert '@AppStorage("BonsaiRC1233APIRuntimeProfile")' in view
assert 'private var apiRuntimeProfile = "safe"' in view
assert 'Text("Safe").tag("safe")' in view
assert 'Text("Flash").tag("flash")' in view
assert 'Text("Full").tag("accelerated")' in view
assert '.disabled(apiServer.isRunning)' in view

# Runtime profiles are explicit and do not alter C2-B identity/checkpoint logic.
assert 'case "flash":' in view
assert 'case "accelerated":' in view
assert 'apiRuntime.flashAttention = true' in view
assert 'apiRuntime.offloadKQV = true' in view
assert 'apiRuntime.opOffload = true' in view
assert 'BonsaiRC1233ActiveAPIRuntimeProfile' in view
assert 'api_runtime_profile=' in view

# Frozen context shape and C2-B mechanics remain in the engine.
assert "params.n_seq_max = 1" in engine
assert "contextParams.n_seq_max = 1" in engine
assert "BonsaiRetainVisionPrefixKV" in engine
assert "apiVisionPrefixReuseKey" in engine

assert 'CURRENT_PROJECT_VERSION: "44"' in project
print("RC1.23.3 build 44 runtime profile A/B contracts: PASS")
