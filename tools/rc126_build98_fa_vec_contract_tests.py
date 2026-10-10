#!/usr/bin/env python3
"""Build98: isolated FA-vec experiment contracts, not GPU numerical certification."""
from pathlib import Path
import importlib.util

ROOT = Path(__file__).resolve().parents[1]
patch_path = ROOT / "tools/rc126_build98_patch_prism_fa_vec_ab.py"
view = (ROOT / "BonsaiLab/ProductionView.swift").read_text()
startup = (ROOT / "BonsaiLab/BonsaiLabApp.swift").read_text()
arm = (ROOT / "BonsaiLab/Build98FAVecAB.swift").read_text()
server = (ROOT / "BonsaiLab/LocalOpenAIServer.swift").read_text()
workflow = (ROOT / ".github/workflows/build-ios.yml").read_text()
project = (ROOT / "project.yml").read_text()
assert 'CURRENT_PROJECT_VERSION: "98"' in project
assert 'RC126APIStartupLifecycle.begin(build: "98")' in view
assert '"build_id": "rc1.26-build98-m5-fa-vec-ab"' in server
assert 'Build98FAVecAB.installAtProcessLaunch()' in startup
assert 'setenv("BONSAI_FA_VEC_ARM", effective, 1)' in arm
assert 'defaults.set("A0", forKey: nextKey)' in arm
assert 'fa_vec_experiment": Build98FAVecAB.snapshot()' in server
assert 'Build 98 · M5 FA-vec 实验' in view
assert 'Text("A0 · 原始 Prism 参数")' in view
assert 'Text("A1 · Q=1, NE=2")' in view
assert 'Text("A2 · Q=1, NE=4")' in view
assert 'build98-m5-fa-vec-ab-unsigned.ipa' in workflow
assert 'rc126_build98_patch_prism_fa_vec_ab.py' in workflow

spec = importlib.util.spec_from_file_location("build98_patch", patch_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
mock = '#include <cstdlib>\n' + module.ANCHOR + '\n'
modified = module.patch(mock)
assert modified.count(module.MARK) == 1
assert 'props_dev->gpu_family == 10' in modified
assert 'std::strcmp(props_dev->desc, "Apple M5 GPU") == 0' in modified
assert 'op->src[1]->type == GGML_TYPE_Q4_0' in modified
assert 'ne01 == 1 && ne11 >= 1024' in modified
assert 'ne00 == 256 && ne20 == 256' in modified
assert 'cfg.Q == 1' in modified
assert 'cfg.NE = 2;' in modified
assert 'cfg.NE = 4;' in modified
assert 'std::strcmp(bonsai_arm, "A1")' in modified
assert 'std::strcmp(bonsai_arm, "A2")' in modified
assert 'atomic_flag' in modified
assert 'BONSAI_FA_VEC_TRACE_PATH' in modified
try:
    module.patch(modified)
except ValueError:
    pass
else:
    raise AssertionError("must fail closed on double patch")

print("PASS Build98 source contracts: A0 inherited, A1/A2 scoped, process-latched, read-only trace")
