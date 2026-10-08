#!/usr/bin/env python3
"""Instrument scheduler reserve inside pinned Prism after Build83+84 patches.

Build85 changes no tensor shapes, model parameters, scheduler logic or buffers.
Each marker is fsync'd via the Build84 trace header only for >=32768.
"""
from pathlib import Path
import sys
if len(sys.argv) != 2:
    raise SystemExit("usage: rc126_build85_patch_prism_scheduler_trace.py <llama-context.cpp>")
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8")
if '#include "bonsai-build84-trace.h"' not in s or "BUILD84_CTX_SCHED_BEGIN" not in s:
    raise SystemExit("Build85 requires Build84 native trace patch first")
def once(before, after, name):
    global s
    n=s.count(before)
    if n!=1:
        raise SystemExit(f"Build85 source drift ({name}): expected 1, got {n}")
    s=s.replace(before,after,1)

once('    LLAMA_LOG_INFO("%s: reserving ...\\n", __func__);',
'''    LLAMA_LOG_INFO("%s: reserving ...\\n", __func__);
    bonsai_build84_trace("BUILD85_SCHED_ENTER n_ctx=%u ubatch=%u", cparams.n_ctx, cparams.n_ubatch);''',"sched entry")
once('    const size_t max_nodes = this->graph_max_nodes(n_tokens);',
'''    bonsai_build84_trace("BUILD85_GRAPH_MAX_NODES_BEGIN n_tokens=%u", n_tokens);
    const size_t max_nodes = this->graph_max_nodes(n_tokens);
    bonsai_build84_trace("BUILD85_GRAPH_MAX_NODES_DONE max_nodes=%zu", max_nodes);''',"max nodes")
once('    gf_res_prev.reset(new llm_graph_result(max_nodes));\n    gf_res_reserve.reset(new llm_graph_result(max_nodes));',
'''    bonsai_build84_trace("BUILD85_GRAPH_RESULT_ALLOC_BEGIN");
    gf_res_prev.reset(new llm_graph_result(max_nodes));
    gf_res_reserve.reset(new llm_graph_result(max_nodes));
    bonsai_build84_trace("BUILD85_GRAPH_RESULT_ALLOC_DONE");''',"graph results")
once('    sched.reset(ggml_backend_sched_new(backend_ptrs.data(), backend_buft.data(), backend_ptrs.size(), max_nodes, cparams.pipeline_parallel, cparams.op_offload));',
'''    bonsai_build84_trace("BUILD85_BACKEND_SCHED_NEW_BEGIN count=%zu", backend_ptrs.size());
    sched.reset(ggml_backend_sched_new(backend_ptrs.data(), backend_buft.data(), backend_ptrs.size(), max_nodes, cparams.pipeline_parallel, cparams.op_offload));
    bonsai_build84_trace("BUILD85_BACKEND_SCHED_NEW_DONE");''',"backend create")
once('        mctx = memory->init_full();',
'''        bonsai_build84_trace("BUILD85_MEMORY_INIT_FULL_BEGIN");
        mctx = memory->init_full();
        bonsai_build84_trace("BUILD85_MEMORY_INIT_FULL_DONE");''',"full memory")
once('    resolve_fused_ops(mctx.get(), n_seqs);',
'''    bonsai_build84_trace("BUILD85_FUSED_RESOLVE_BEGIN");
    resolve_fused_ops(mctx.get(), n_seqs);
    bonsai_build84_trace("BUILD85_FUSED_RESOLVE_DONE");''',"fused resolve")
once('''        auto * gf = graph_reserve(n_tokens, n_seqs, n_outputs_pp, mctx.get(),
                model.hparams.no_alloc, model.hparams.no_alloc ? backend_buf_exp_size.data() : nullptr);''',
'''        bonsai_build84_trace("BUILD85_PP1_BEGIN n_tokens=%u", n_tokens);
        auto * gf = graph_reserve(n_tokens, n_seqs, n_outputs_pp, mctx.get(),
                model.hparams.no_alloc, model.hparams.no_alloc ? backend_buf_exp_size.data() : nullptr);
        bonsai_build84_trace("BUILD85_PP1_RETURN success=%d", gf != nullptr);''',"prompt first")
once('        auto * gf = graph_reserve(n_seqs, n_seqs, n_seqs, mctx.get(), model.hparams.no_alloc);',
'''        bonsai_build84_trace("BUILD85_TG_BEGIN n_seqs=%u", n_seqs);
        auto * gf = graph_reserve(n_seqs, n_seqs, n_seqs, mctx.get(), model.hparams.no_alloc);
        bonsai_build84_trace("BUILD85_TG_RETURN success=%d", gf != nullptr);''',"token generation")
once('        auto * gf = graph_reserve(n_tokens, n_seqs, n_outputs_pp, mctx.get(), model.hparams.no_alloc);',
'''        bonsai_build84_trace("BUILD85_PP2_BEGIN n_tokens=%u", n_tokens);
        auto * gf = graph_reserve(n_tokens, n_seqs, n_outputs_pp, mctx.get(), model.hparams.no_alloc);
        bonsai_build84_trace("BUILD85_PP2_RETURN success=%d", gf != nullptr);''',"prompt again")
once('    LLAMA_LOG_INFO("%s: reserve took %.2f ms, sched copies = %d\\n",',
'''    bonsai_build84_trace("BUILD85_SCHED_DONE");
    LLAMA_LOG_INFO("%s: reserve took %.2f ms, sched copies = %d\\n",''',"sched done")
once('    ggml_backend_sched_reset(sched.get());\n\n    // when the scheduler is reset,',
'''    bonsai_build84_trace("BUILD85_GRAPH_RESET_BEGIN n_tokens=%u", n_tokens);
    ggml_backend_sched_reset(sched.get());
    bonsai_build84_trace("BUILD85_GRAPH_RESET_DONE");

    // when the scheduler is reset,''',"graph reset")
once('    auto * gf = model.build_graph(gparams);',
'''    bonsai_build84_trace("BUILD85_MODEL_BUILD_GRAPH_BEGIN n_tokens=%u", n_tokens);
    auto * gf = model.build_graph(gparams);
    bonsai_build84_trace("BUILD85_MODEL_BUILD_GRAPH_DONE nodes=%d", gf ? ggml_graph_n_nodes(gf) : -1);''',"graph build")
once('    } else if (!ggml_backend_sched_reserve(sched.get(), gf)) {',
'''    } else if ((bonsai_build84_trace("BUILD85_BACKEND_RESERVE_BEGIN"), false) ||
               !ggml_backend_sched_reserve(sched.get(), gf)) {
        bonsai_build84_trace("BUILD85_BACKEND_RESERVE_FAILED");''',"scheduler reserve")
# The conditional technique above cannot emit success until after the block;
# write an unconditional success stage after the guarded reserve branch.
once('''        return nullptr;
    }

    return gf;
}''',
'''        return nullptr;
    }
    bonsai_build84_trace("BUILD85_BACKEND_GRAPH_RESERVE_DONE split_only=%d", (int)split_only);

    return gf;
}''',"graph reserve done")
p.write_text(s,encoding="utf-8")
print("RC1.26 Build 85 fine-grained scheduler trace patch: PASS")
