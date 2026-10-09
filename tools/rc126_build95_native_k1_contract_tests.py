#!/usr/bin/env python3
"""Runnable Build95 K1 patch contract tests (also used on macOS CI).
Verify the exact upstream 4->5 transplant and fail-closed non-partial writing.
"""
import importlib.util
import tempfile
from pathlib import Path

here = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("k1patch", here / "rc126_build95_patch_prism_ptq1_dense5.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

def fixtures(root):
    h = root / "ggml/src/ggml-metal/ggml-metal-impl.h"
    d = root / "ggml/src/ggml-metal/ggml-metal-device.cpp"
    k = root / "ggml/src/ggml-metal/kernels/mul_mv.metal"
    for p in (h,d,k): p.parent.mkdir(parents=True,exist_ok=True)
    h.write_text("#define N_R0_PTQ1_0 4\n#define N_SG_PTQ1_0 1\n")
    d.write_text(
        "case GGML_TYPE_PTQ1_0:\n            {\n                nsg = N_SG_PTQ1_0;\n"
        "                nr0 = N_R0_PTQ1_0;\n            } break;\n"
        "ggml_metal_library_get_pipeline_mul_mv_id(\n"
        "case GGML_TYPE_PTQ1_0:\n            {\n                nsg = N_SG_PTQ1_0;\n"
        "                nr0 = N_R0_PTQ1_0;\n            } break;\n"
    )
    k.write_text(
        "kernel_mul_mv_ptq1_0_f32_impl<N_R0_PTQ1_0, constant>();\n"
        "kernel_mul_mv_id<mmv_fn<kernel_mul_mv_ptq1_0_f32_impl<N_R0_PTQ1_0>>>;\n"
    )
    return h,d,k

with tempfile.TemporaryDirectory() as td:
    root=Path(td);h,d,k=fixtures(root)
    edits=mod.plan(root)
    assert len(edits)==3
    assert "#define N_R0_PTQ1_0 5" in edits[h]
    assert "#define N_R0_ID_PTQ1_0 4" in edits[h]
    assert edits[d].split("ggml_metal_library_get_pipeline_mul_mv_id(")[0] == d.read_text().split("ggml_metal_library_get_pipeline_mul_mv_id(")[0]
    assert "kernel_mul_mv_ptq1_0_f32_impl<N_R0_PTQ1_0" in edits[k]
    assert "kernel_mul_mv_ptq1_0_f32_impl<N_R0_ID_PTQ1_0" in edits[k]
    for p,s in edits.items():p.write_text(s)
    try: mod.plan(root)
    except RuntimeError: pass
    else: raise AssertionError("Must reject second patch")
    print("PASS K1 synthetic patch exact anchors, dense unchanged, ID isolated, reapply rejected")

with tempfile.TemporaryDirectory() as td:
    root=Path(td);h,d,k=fixtures(root)
    k.write_text("CORRUPT SOURCE")
    before=[p.read_bytes() for p in (h,d,k)]
    try:mod.plan(root)
    except RuntimeError: pass
    else:raise AssertionError("Must refuse malformed source")
    assert [p.read_bytes() for p in (h,d,k)]==before
    print("PASS K1 fail closed and no partial writes on malformed anchors")
