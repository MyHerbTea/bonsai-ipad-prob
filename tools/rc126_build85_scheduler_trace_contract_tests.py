from pathlib import Path
root=Path(__file__).resolve().parents[1]
view=(root/"BonsaiLab/ProductionView.swift").read_text()
engine=(root/"BonsaiLab/BonsaiEngine.swift").read_text()
server=(root/"BonsaiLab/LocalOpenAIServer.swift").read_text()
workflow=(root/".github/workflows/build-ios.yml").read_text()
patch=(root/"tools/rc126_build85_patch_prism_scheduler_trace.py").read_text()
assert 'CURRENT_PROJECT_VERSION: "100"' in (root/"project.yml").read_text()
assert 'RC126APIStartupLifecycle.begin(build: "100"' in view
assert '"build_id": "rc1.26-build100-b16-accel-guarded"' in server
assert "build85_scheduler_reserve_trace_supported" in server
assert "build=89" in engine
assert "[BUILD 84 NATIVE CONTEXT CRASH TRACE]" in view
for marker in (
    "BUILD85_SCHED_ENTER",
    "BUILD85_BACKEND_SCHED_NEW_BEGIN",
    "BUILD85_FUSED_RESOLVE_BEGIN",
    "BUILD85_MODEL_BUILD_GRAPH_BEGIN",
    "BUILD85_BACKEND_RESERVE_BEGIN",
    "BUILD85_BACKEND_RESERVE_FAILED",
    "BUILD85_PP1_BEGIN",
    "BUILD85_TG_BEGIN",
    "BUILD85_PP2_BEGIN",
    "BUILD85_SCHED_DONE",
):
    assert marker in patch, marker
assert "rc126_build85_patch_prism_scheduler_trace.py" in workflow
assert "BonsaiLab-v1-RC1.26-build100-b16-accel-guarded-unsigned.ipa" in workflow
print("RC1.26 Build 85 scheduler trace contracts: PASS")
