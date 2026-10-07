from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
view = (ROOT / "BonsaiLab/ProductionView.swift").read_text(encoding="utf-8")
server = (ROOT / "BonsaiLab/LocalOpenAIServer.swift").read_text(encoding="utf-8")
project = (ROOT / "project.yml").read_text(encoding="utf-8")
workflow = (ROOT / ".github/workflows/build-ios.yml").read_text(encoding="utf-8")

assert 'CURRENT_PROJECT_VERSION: "80"' in project
assert 'RC126APIStartupLifecycle.begin(build: "80")' in view
assert "RC1.26 Build 80 Long-Context Tier Reload Fix" in view
assert '"build_id": "rc1.26-build80-long-context-tier-reload-fix"' in server

# One shared policy must drive fresh start and context-switch paths.
assert "private func applyBuild80LongContextPolicy(" in view
assert view.count("applyBuild80LongContextPolicy(") == 3  # declaration + two call sites
assert 'source: "fresh_start"' in view
assert 'source: "context_switch"' in view

# Intended Build79 memory policy must remain unchanged.
assert "min(apiRuntime.gpuLayers, 56)" in view
assert "min(apiRuntime.gpuLayers, 40)" in view
assert "min(apiRuntime.gpuLayers, 24)" in view
assert "min(apiRuntime.batch, 8)" in view
assert "min(apiRuntime.batch, 4)" in view

# Crossing a model-residency tier must reload; context-only rebuild cannot
# change llama_model_params.n_gpu_layers after the model has been loaded.
assert "previouslyLoadedGPULayers" in view
assert "requiresModelReload" in view
assert "await sharedEngine.unloadAll()" in view
assert "nanoseconds: 600_000_000" in view
assert "_ = try await sharedEngine.loadModel(" in view
assert "BonsaiBuild80ModelReloadRequired" in view
assert "BonsaiBuild80ModelReloadPerformed" in view
assert "BonsaiBuild80ReloadStage" in view

# Same-tier changes still use the lower-peak context-only path.
assert ".reconfigureTextContextKeepingModel(" in view

# Runtime evidence must tell us which path was actually taken on device.
for field in [
    "build80_policy_source",
    "build80_target_context",
    "build80_previous_gpu_layers",
    "build80_target_gpu_layers",
    "build80_model_reload_required",
    "build80_model_reload_performed",
    "build80_reload_stage",
]:
    assert field in server, field

assert "RC1.26 Build 80 tier reload contracts" in workflow
assert "tools/rc126_build80_tier_reload_contract_tests.py" in workflow
assert "build80-long-context-tier-reload-fix-unsigned.ipa" in workflow

print("RC1.26 Build 80 tier reload contracts: PASS")
