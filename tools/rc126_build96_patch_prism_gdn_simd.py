#!/usr/bin/env python3
"""Native K2: fail-closed transfer of Prism 445fa820 GDN SIMD into frozen Prism.

Input must be a clean pinned Prism adfffbe checkout (or the same tree with
Build83-89 Bonsai non-Metal scheduler/KV patches). Never silently upgrade Prism.
"""
import argparse
import subprocess
from pathlib import Path

PRISM_PIN = "adfffbe41b2cabcd51fff326ab045662265062bb"
OPS = "ggml/src/ggml-metal/ggml-metal-ops.cpp"
GDN = "ggml/src/ggml-metal/kernels/gated_delta_net.metal"
FILES = (OPS, GDN)

def cmd(root, *args):
    proc = subprocess.run(["git", "-C", str(root), *args],
                          check=False, capture_output=True, text=True)
    if proc.returncode:
        raise RuntimeError("git " + " ".join(args) + ": " + (proc.stderr or proc.stdout))
    return proc.stdout.strip()

def main():
    p = argparse.ArgumentParser()
    p.add_argument("prism_root", type=Path)
    p.add_argument("--check-only", action="store_true")
    a = p.parse_args()
    root = a.prism_root.resolve()
    patch = (Path(__file__).resolve().parent/"patches/k2_prism_445fa820_gdn_4rows.patch").resolve()
    assert patch.is_file(), "missing vendored, source-reviewed patch"
    assert cmd(root, "rev-parse", "HEAD") == PRISM_PIN, "wrong native Prism base"

    ops = (root / OPS).read_text(encoding="utf-8")
    gdn = (root / GDN).read_text(encoding="utf-8")
    # These exact expectations distinguish the original GDN row/SIMD layout.
    baseline_dispatch = "ggml_metal_encoder_dispatch_threadgroups(enc, op->src[2]->ne[0]/nsg, op->src[2]->ne[1], op->src[2]->ne[3], 32, nsg, 1);"
    assert ops.count(baseline_dispatch) == 1, "unexpected original GDN dispatcher"
    assert gdn.count("const uint i20 = tgpig.x*NSG + ty;") == 2, "expected active and #else fallback GDN lane mappings"
    assert gdn.count("s_k = simd_sum(s_k);") == 1, "unexpected original GDN reduction"
    assert gdn.count("y = simd_sum(y);") == 1, "unexpected original GDN output reduction"
    patch_text = patch.read_text(encoding="utf-8")
    changed = [line[len("diff --git a/"):].split(" b/", 1)[0] for line in patch_text.splitlines() if line.startswith("diff --git a/")]
    assert changed == list(FILES), f"patch changed unexpected source files: {changed}"
    assert "LANES_PER_ROW = 8" in patch_text and "(4 * nsg)" in patch_text

    cmd(root, "apply", "--check", "--whitespace=error", str(patch))
    if a.check_only:
        print("PASS K2 pinned Prism exact patch preflight (no writes)")
        return

    cmd(root, "apply", "--whitespace=error", str(patch))
    now_ops = (root / OPS).read_text(encoding="utf-8")
    now_gdn = (root / GDN).read_text(encoding="utf-8")
    assert baseline_dispatch not in now_ops
    assert "op->src[2]->ne[0] / (4 * nsg)" in now_ops
    assert "LANES_PER_ROW = 8" in now_gdn
    assert "simd_shuffle_xor(s_k, offset)" in now_gdn
    assert "simd_shuffle_xor(y, offset)" in now_gdn
    cmd(root, "diff", "--check")
    print("PASS Native K2 GDN 4-row SIMD patch applied on pinned Prism; CI compile/device numeric tests required")

if __name__ == "__main__":
    main()
