from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

view = (ROOT / "BonsaiLab/ProductionView.swift").read_text(encoding="utf-8")
server = (ROOT / "BonsaiLab/LocalOpenAIServer.swift").read_text(encoding="utf-8")
types = (ROOT / "BonsaiLab/LabTypes.swift").read_text(encoding="utf-8")
engine = (ROOT / "BonsaiLab/BonsaiEngine.swift").read_text(encoding="utf-8")
project = (ROOT / "project.yml").read_text(encoding="utf-8")
workflow = (ROOT / ".github/workflows/build-ios.yml").read_text(encoding="utf-8")

# The runtime validator already supports the whole M5 context ladder.
assert "guard context >= 256 && context <= 8192" in types

for value in ["512", "768", "1024", "2048", "3072", "4096", "6144", "8192"]:
    assert f'"{value}"' in view, value
    assert f'.tag("{value}")' in view, value

assert 'private var apiContextProfile = "4096"' in view
assert 'Text("4096 · recommended").tag("4096")' in view
assert 'Text("6144 · aggressive").tag("6144")' in view
assert 'Text("8192 · extreme").tag("8192")' in view
assert ".pickerStyle(.menu)" in view
assert "2048 仅保留为认证对照" in view

# Build identity must be unambiguous.
assert 'CURRENT_PROJECT_VERSION: "77"' in project
assert '"build_id": "rc1.26-build77-extended-context-lab"' in server
assert 'RC126APIStartupLifecycle.begin(build: "77")' in view
assert "RC1.26 Build 77 M5 Extended Context Lab" in view

# Keep the already-debugged Build 76 text path intact for now; Build 77 is
# deliberately a capacity unlock, not a claim that KV reuse is fixed.
for marker in [
    "textKVResidentTokens",
    "textKVResidentContext",
    "llama_memory_seq_rm(",
    "post_generation_tail_trim_failed",
]:
    assert marker in engine, marker

# Frozen safety/performance boundaries remain present.
assert "RC1.26 Build 75 cold-start guard contracts" in workflow
assert "tools/rc126_build75_api_cold_start_contract_tests.py" in workflow
assert 'setenv("GGML_METAL_TENSOR_DISABLE", "1", 1)' in engine

assert "RC1.26 Build 77 extended context contracts" in workflow
assert "tools/rc126_build77_extended_context_contract_tests.py" in workflow

package_marker = "\n      - name: Package unsigned IPA\n"
upload_marker = "\n      - name: Upload artifact\n"
package_start = workflow.index(package_marker)
upload_start = workflow.index(upload_marker, package_start)
package_block = workflow[package_start:upload_start]
assert "BonsaiLab-v1-RC1.26-build77-extended-context-lab-unsigned.ipa" in package_block
assert "build76-text-kv-reuse-lab-unsigned.ipa" not in package_block

print("RC1.26 Build 77 Extended Context contracts: PASS")
