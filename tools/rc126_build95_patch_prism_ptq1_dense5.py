#!/usr/bin/env python3
"""Fail-closed minimal transplant of Prism upstream commit 5e9365f (2026-10-08).
Only edits dense row tile and preserves MUL_MAT_ID's proven four-row path.
Target pinned Prism adfffbe41b2cabcd51fff326ab045662265062bb,
after existing Bonsai Build83-89 patches, BEFORE XCFramework compilation.
"""
import argparse
from pathlib import Path


def replace_once(content: str, before: str, after: str, label: str) -> str:
    matches = content.count(before)
    if matches != 1:
        raise RuntimeError(f"{label}: expected one exact source anchor, got {matches}")
    if after in content:
        raise RuntimeError(f"{label}: target already present, refusing double application")
    return content.replace(before, after, 1)


def plan(root: Path) -> dict[Path, str]:
    header = root / "ggml/src/ggml-metal/ggml-metal-impl.h"
    device = root / "ggml/src/ggml-metal/ggml-metal-device.cpp"
    kernel = root / "ggml/src/ggml-metal/kernels/mul_mv.metal"

    h = header.read_text(encoding="utf-8")
    h = replace_once(
        h,
        "#define N_R0_PTQ1_0 4\n#define N_SG_PTQ1_0 1",
        "// The dense kernel can amortize each activation load across five output rows.\n"
        "// Keep MUL_MAT_ID at four: its five-row specialization fails numerical validation.\n"
        "#define N_R0_PTQ1_0 5\n#define N_SG_PTQ1_0 1\n#define N_R0_ID_PTQ1_0 4",
        "dense row constant and safe ID split"
    )

    d = device.read_text(encoding="utf-8")
    anchor = "ggml_metal_library_get_pipeline_mul_mv_id("
    # Isolate MUL_MAT_ID pipeline selector; do NOT edit normal dense selector.
    if d.count(anchor) != 1:
        raise RuntimeError("MUL_MAT_ID selector anchor not unique")
    left, right = d.split(anchor, 1)
    right = replace_once(
        right,
        "case GGML_TYPE_PTQ1_0:\n            {\n                nsg = N_SG_PTQ1_0;\n                nr0 = N_R0_PTQ1_0;\n            } break;",
        "case GGML_TYPE_PTQ1_0:\n            {\n                nsg = N_SG_PTQ1_0;\n                nr0 = N_R0_ID_PTQ1_0;\n            } break;",
        "MUL_MAT_ID pipeline row constant"
    )
    d = left + anchor + right

    k = kernel.read_text(encoding="utf-8")
    k = replace_once(
        k,
        "kernel_mul_mv_id<mmv_fn<kernel_mul_mv_ptq1_0_f32_impl<N_R0_PTQ1_0>>>;",
        "kernel_mul_mv_id<mmv_fn<kernel_mul_mv_ptq1_0_f32_impl<N_R0_ID_PTQ1_0>>>;",
        "MUL_MAT_ID template instantiation"
    )
    assert "kernel_mul_mv_ptq1_0_f32_impl<N_R0_PTQ1_0" in k, "Dense shader was unexpectedly altered"
    assert "N_R0_PTQ1_0 5" in h
    assert "N_R0_ID_PTQ1_0 4" in h
    return {header:h, device:d, kernel:k}


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("prism_root",type=Path)
    args=parser.parse_args()
    changes=plan(args.prism_root)
    # All source preconditions checked before any file is written.
    for path,new in changes.items():
        path.write_text(new,encoding="utf-8")
        print(f"K1 PATCH: {path.relative_to(args.prism_root)}")
    print("K1 NATIVE PTQ1 DENSE5 / ID4: PASS (source patch only; no numeric/device claim)")


if __name__=="__main__":
    main()
