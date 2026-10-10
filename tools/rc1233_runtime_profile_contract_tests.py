from pathlib import Path
import re

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

assert "contextParams.n_seq_max =" in engine and "config.context == 32_768 && textKVCheckpointEnabled ? 2 : 1" in engine
assert "params.n_seq_max = 1" in engine
assert "BonsaiRetainVisionPrefixKV" in engine
assert "apiVisionPrefixReuseKey" in engine

match = re.search(r'CURRENT_PROJECT_VERSION:\s*"([0-9]+)"', project)
assert match is not None
assert int(match.group(1)) >= 45

print("RC1.23.3 accelerated runtime baseline contracts: PASS")
