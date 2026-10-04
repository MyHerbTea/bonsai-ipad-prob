from pathlib import Path

root = Path(__file__).resolve().parents[1]
view = (root / "BonsaiLab" / "ProductionView.swift").read_text()
project = (root / "project.yml").read_text()
engine = (root / "BonsaiLab" / "BonsaiEngine.swift").read_text()

assert '@AppStorage("BonsaiRC1233APIRuntimeProfile")' in view
assert 'private var apiRuntimeProfile = "accelerated"' in view
assert 'Text("Safe").tag("safe")' in view
assert 'Text("Full").tag("accelerated")' in view
assert 'Text("Flash").tag("flash")' not in view
assert 'if apiRuntimeProfile == "flash"' in view
assert 'case "flash":' not in view
assert 'case "accelerated":' in view

assert "contextParams.n_seq_max = 1" in engine
assert "params.n_seq_max = 1" in engine
assert "BonsaiRetainVisionPrefixKV" in engine
assert "apiVisionPrefixReuseKey" in engine

assert 'CURRENT_PROJECT_VERSION: "45"' in project
print("RC1.23.3 build 45 accelerated baseline contracts: PASS")
