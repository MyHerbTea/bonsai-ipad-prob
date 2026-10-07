from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

view = (ROOT / "BonsaiLab/ProductionView.swift").read_text(encoding="utf-8")
server = (ROOT / "BonsaiLab/LocalOpenAIServer.swift").read_text(encoding="utf-8")
types = (ROOT / "BonsaiLab/LabTypes.swift").read_text(encoding="utf-8")
engine = (ROOT / "BonsaiLab/BonsaiEngine.swift").read_text(encoding="utf-8")
project = (ROOT / "project.yml").read_text(encoding="utf-8")
workflow = (ROOT / ".github/workflows/build-ios.yml").read_text(encoding="utf-8")

assert "guard context >= 256 && context <= 8192" in types

# Build 78 exposes only the device-safe boundary ladder.
for value in ["512", "768", "1024", "2048", "3072", "4096", "4608", "5120", "5632"]:
    assert f'.tag("{value}")' in view, value

assert '.tag("6144")' not in view
assert '.tag("8192")' not in view
assert '"6144", "8192"' in view  # migration guard only
assert '"4608", "5120", "5632"' in view
assert 'private var apiContextProfile = "4096"' in view
assert 'Text("4096 · verified").tag("4096")' in view
assert 'Text("4608 · probe").tag("4608")' in view
assert 'Text("5120 · probe").tag("5120")' in view
assert 'Text("5632 · edge").tag("5632")' in view
assert "BonsaiRC126Build78UnsafeContextMigratedFrom" in view

# >4096 capacity mode must override the inherited Phase2F 32x32 launch shape.
assert "let build78CapacityMode =" in view
assert "selectedAPIContext > 4096" in view
assert "min(apiRuntime.batch, 16)" in view
assert "min(apiRuntime.ubatch, 16)" in view
assert "BonsaiRC126Build78CapacityMode" in view
assert "BonsaiRC126Build78EffectiveBatch" in view
assert "BonsaiRC126Build78EffectiveUBatch" in view

assert 'CURRENT_PROJECT_VERSION: "78"' in project
assert '"build_id": "rc1.26-build78-context-boundary-lab"' in server
assert 'RC126APIStartupLifecycle.begin(build: "78")' in view
assert "RC1.26 Build 78 M5 Context Boundary Lab" in view

# Frozen safety boundaries remain intact.
assert "llama_init_from_model" in engine
assert 'setenv("GGML_METAL_TENSOR_DISABLE", "1", 1)' in engine
assert "RC1.26 Build 75 cold-start guard contracts" in workflow
assert "tools/rc126_build75_api_cold_start_contract_tests.py" in workflow

assert "RC1.26 Build 78 context boundary contracts" in workflow
assert "tools/rc126_build78_context_boundary_contract_tests.py" in workflow

package_marker = "\n      - name: Package unsigned IPA\n"
upload_marker = "\n      - name: Upload artifact\n"
package_start = workflow.index(package_marker)
upload_start = workflow.index(upload_marker, package_start)
package_block = workflow[package_start:upload_start]
assert "BonsaiLab-v1-RC1.26-build78-context-boundary-lab-unsigned.ipa" in package_block
assert "build77-extended-context-lab-unsigned.ipa" not in package_block

print("RC1.26 Build 78 Context Boundary contracts: PASS")
