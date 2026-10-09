#!/usr/bin/env python3
"""Build96 native K2 source and experiment isolation contract.
Not a substitute for device numerical testing.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
patch = (root/"tools/patches/k2_prism_445fa820_gdn_4rows.patch").read_text()
script = (root/"tools/rc126_build96_patch_prism_gdn_simd.py").read_text()
workflow = (root/".github/workflows/build-ios.yml").read_text()
server = (root/"BonsaiLab/LocalOpenAIServer.swift").read_text()
view = (root/"BonsaiLab/ProductionView.swift").read_text()
project = (root/"project.yml").read_text()

paths = re.findall(r"^diff --git a/(.*?) b/.*?$", patch, flags=re.M)
assert paths == [
    "ggml/src/ggml-metal/ggml-metal-ops.cpp",
    "ggml/src/ggml-metal/kernels/gated_delta_net.metal"
], paths
assert "op->src[2]->ne[0] / (4 * nsg)" in patch
assert "LANES_PER_ROW = 8" in patch
assert "simd_shuffle_xor(s_k, offset)" in patch
assert "simd_shuffle_xor(y, offset)" in patch
assert "N_R0_PTQ1_0" not in patch
assert "ggml-metal-device.cpp" not in patch
assert "src/models/qwen35" not in patch
assert "PRISM_PIN = \"adfffbe41b2cabcd51fff326ab045662265062bb\"" in script
assert 'CURRENT_PROJECT_VERSION: "96"' in project
assert 'RC126APIStartupLifecycle.begin(build: "96")' in view
assert '"build_id": "rc1.26-build96-native-k2-gdn-simd"' in server
assert '"schema": "bonsai-build94-execution-v1"' in server
assert 'Build94BatchExperiment.select(context: context)' in view
assert "rc126_build96_patch_prism_gdn_simd.py" in workflow
assert "k2_prism_445fa820_gdn_4rows.patch" not in workflow or "rc126_build96_patch_prism_gdn_simd.py" in workflow
assert "rc126_build95_patch_prism_ptq1_dense5.py" not in workflow
assert 'N_R0_PTQ1_0 4' in workflow
assert "build96-native-k2-gdn-simd-unsigned.ipa" in workflow
assert "Build96-Native-K2-GDN-SIMD" in workflow
assert "test-backend-ops" in workflow
print("PASS Build96 K2 GDN exact two-file patch, PTQ1 baseline4 isolation, CI identity and inherited guard checks")
