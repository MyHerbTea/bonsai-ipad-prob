#!/usr/bin/env python3
"""Apply the narrow M5 Q4_0 single-query FA-vec experiment to pinned Prism.

A0 is bit-for-bit the upstream tuning decision. A1/A2 change only cfg.NE for
an explicitly gated M5 256/256 Q4_0 decode shape. No kernel math is modified.
"""
from pathlib import Path
import sys

MARK = "BONSAI_BUILD98_FA_VEC_AB"
ANCHOR = """        int nqptg = cfg.Q;                             // queries per threadgroup"""
HEADER = """#include <atomic>
#include <cstdio>
#include <cstring>
"""
INSERT = r"""
        // BONSAI_BUILD98_FA_VEC_AB
        // One-process, one-shot experiment. No remote API can change this env
        // value: the iOS app sets it once before any model/context is created.
        // The fallback to Prism's decision is exact unless ALL guards match.
        const char * bonsai_arm = std::getenv("BONSAI_FA_VEC_ARM");
        const bool bonsai_m5_q4_decode =
                props_dev->gpu_family == 10 &&
                std::strcmp(props_dev->desc, "Apple M5 GPU") == 0 &&
                op->src[1]->type == GGML_TYPE_Q4_0 &&
                ne01 == 1 && ne11 >= 1024 &&
                ne00 == 256 && ne20 == 256;
        if (bonsai_m5_q4_decode && bonsai_arm != nullptr && cfg.Q == 1) {
            // A0 intentionally does not override Prism's native configuration.
            if (std::strcmp(bonsai_arm, "A1") == 0) {
                cfg.NE = 2;
            } else if (std::strcmp(bonsai_arm, "A2") == 0) {
                cfg.NE = 4;
            }
        }
        if (bonsai_m5_q4_decode) {
            static std::atomic_flag bonsai_logged = ATOMIC_FLAG_INIT;
            if (!bonsai_logged.test_and_set(std::memory_order_relaxed)) {
                if (const char * path = std::getenv("BONSAI_FA_VEC_TRACE_PATH")) {
                    if (FILE * fp = std::fopen(path, "w")) {
                        std::fprintf(fp,
                                "matched=1\\narm=%s\\ndevice=%s\\ngpu_family=%d\\n"
                                "kv_type=Q4_0\\nq_rows=%lld\\nkv_len=%lld\\n"
                                "dk=%lld\\ndv=%lld\\nQ=%d\\nNE=%d\\n",
                                bonsai_arm ? bonsai_arm : "A0",
                                props_dev->desc, props_dev->gpu_family,
                                (long long) ne01, (long long) ne11,
                                (long long) ne00, (long long) ne20,
                                (int) cfg.Q, (int) cfg.NE);
                        std::fclose(fp);
                    }
                }
            }
        }
"""
def patch(s: str) -> str:
    if MARK in s:
        raise ValueError("already patched")
    if s.count(ANCHOR) != 1:
        raise ValueError(f"expected exactly one FA-vec anchor, found {s.count(ANCHOR)}")
    if s.count('#include <cstdlib>') != 1:
        raise ValueError("Prism include anchor changed")
    s = s.replace('#include <cstdlib>\n', '#include <cstdlib>\n' + HEADER, 1)
    return s.replace(ANCHOR, INSERT + ANCHOR, 1)

def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: patch.py path/to/ggml-metal-ops.cpp")
    path = Path(sys.argv[1])
    src = path.read_text()
    updated = patch(src)
    path.write_text(updated)
    print("PASS: Build98 narrow M5 Q4_0 FA-vec AB patch applied")

if __name__ == "__main__":
    main()
