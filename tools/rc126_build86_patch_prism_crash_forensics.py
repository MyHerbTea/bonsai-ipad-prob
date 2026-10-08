#!/usr/bin/env python3
"""Build86 crash forensics v2: native fused probes and ggml scheduler passes.

Apply after Build83, Build84, Build85 scripts to pinned Prism adfffbe41.
Does not alter computation, allocation strategy, fusion, KV, or 16K behavior.
"""
from pathlib import Path
import sys
if len(sys.argv) != 3:
    raise SystemExit("usage: patch_build86.py <llama-context.cpp> <ggml-backend.cpp>")
ctx_path, backend_path = (Path(x) for x in sys.argv[1:])
ctx=ctx_path.read_text(encoding="utf-8")
backend=backend_path.read_text(encoding="utf-8")
if "BUILD85_FUSED_RESOLVE_BEGIN" not in ctx or "BUILD84_CTX_SCHED_BEGIN" not in ctx:
    raise SystemExit("Build86 requires Build84 and Build85 upstream patches first")
if "BUILD86_SPLIT_PASS1_BEGIN" in backend:
    raise SystemExit("Build86 patch already applied: abort to prevent duplicate tracing")

def patch_one(data, old, new, name):
    matches=data.count(old)
    if matches != 1:
        raise SystemExit(f"Build86 native source drift ({name}): expected 1, found {matches}")
    return data.replace(old, new, 1)

ctx=patch_one(ctx,
'''        const uint32_t n_tokens_probe = probe.n_tokens_per_seq*n_seqs;

        auto * gf = graph_reserve(n_tokens_probe, n_seqs, n_tokens_probe, mctx, true);''',
'''        const uint32_t n_tokens_probe = probe.n_tokens_per_seq*n_seqs;
        bonsai_build84_trace("BUILD86_FUSED_PROBE_BEGIN name=%s tokens=%u", probe.name, n_tokens_probe);

        auto * gf = graph_reserve(n_tokens_probe, n_seqs, n_tokens_probe, mctx, true);
        bonsai_build84_trace("BUILD86_FUSED_PROBE_GRAPH_DONE name=%s ok=%d", probe.name, gf != nullptr);''',
"fused probe graph")

ctx=patch_one(ctx,
'''        bool device_mismatch = false;
        for (const auto & node : get_gf_res_reserve()->get_fused_nodes()) {''',
'''        bool device_mismatch = false;
        bonsai_build84_trace("BUILD86_FUSED_PROBE_ASSIGN_BEGIN name=%s count=%zu",
                probe.name, get_gf_res_reserve()->get_fused_nodes().size());
        for (const auto & node : get_gf_res_reserve()->get_fused_nodes()) {''',
"fused probe assignments")

ctx=patch_one(ctx,
'''        if (device_mismatch) {
            enabled = false;''',
'''        bonsai_build84_trace("BUILD86_FUSED_PROBE_ASSIGN_DONE name=%s mismatch=%d", probe.name, (int)device_mismatch);
        if (device_mismatch) {
            enabled = false;''',
"probe assign done")

ctx=patch_one(ctx,
'''        } else {
            ggml_backend_sched_split_graph(sched.get(), gf);
        }
    } else if ((bonsai_build84_trace("BUILD85_BACKEND_RESERVE_BEGIN"), false) ||''',
'''        } else {
            bonsai_build84_trace("BUILD86_CONTEXT_SPLIT_BEGIN nodes=%d", ggml_graph_n_nodes(gf));
            ggml_backend_sched_split_graph(sched.get(), gf);
            bonsai_build84_trace("BUILD86_CONTEXT_SPLIT_DONE splits=%d", ggml_backend_sched_get_n_splits(sched.get()));
        }
    } else if ((bonsai_build84_trace("BUILD85_BACKEND_RESERVE_BEGIN"), false) ||''',
"context graph splitter")

backend=patch_one(backend,
'#include "ggml-backend-impl.h"',
'#include "ggml-backend-impl.h"\n// Installed by Build84 patch in Prism/src; enabled only for experimental >=32K.\n#include "../../src/bonsai-build84-trace.h"',
"ggml include")

backend=patch_one(backend,
'''void ggml_backend_sched_split_graph(ggml_backend_sched_t sched, struct ggml_cgraph * graph) {
    // reset splits''',
'''void ggml_backend_sched_split_graph(ggml_backend_sched_t sched, struct ggml_cgraph * graph) {
    bonsai_build84_trace("BUILD86_SPLIT_ENTER nodes=%d leafs=%d backends=%d hash_size=%zu context_bytes=%zu",
            graph->n_nodes, graph->n_leafs, sched->n_backends, sched->hash_set.size, sched->context_buffer_size);
    // reset splits''',
"ggml splitter entry")

for num, comment, payload in (
    (1, "// pass 1: assign backends to ops with pre-allocated inputs", "nodes=%d leafs=%d"),
    (2, "// pass 2: expand current backend assignments", "nodes=%d leafs=%d"),
    (3, "// pass 3: upgrade nodes to higher prio backends with compatible buffer types", "nodes=%d leafs=%d"),
    (4, "// pass 4: assign backends to remaining src from dst and view_src", "nodes=%d leafs=%d"),
    (5, "// pass 5: split graph, find tensors that need to be copied", "nodes=%d leafs=%d"),
):
    backend=patch_one(backend,
        "    "+comment,
        f'    bonsai_build84_trace("BUILD86_SPLIT_PASS{num}_BEGIN {payload}", graph->n_nodes, graph->n_leafs);\n    '+comment,
        f"ggml pass {num}")

backend=patch_one(backend,
'''        GGML_ASSERT(*cur_backend_id != -1);
    }

    bonsai_build84_trace("BUILD86_SPLIT_PASS5_BEGIN''',
'''        if (*cur_backend_id == -1) {
            bonsai_build84_trace("BUILD86_INVALID_ASSIGNMENT_PASS4 op=%d", (int)node->op);
        }
        GGML_ASSERT(*cur_backend_id != -1);
    }

    bonsai_build84_trace("BUILD86_SPLIT_PASS5_BEGIN''',
"unassigned backend assert")

backend=patch_one(backend,
'''        int cur_backend_id = split->backend_id;
        for (; i < graph->n_nodes; i++) {
            struct ggml_tensor * node = graph->nodes[i];''',
'''        int cur_backend_id = split->backend_id;
        for (; i < graph->n_nodes; i++) {
            if ((i % 128) == 0) {
                bonsai_build84_trace("BUILD86_PASS5_HEARTBEAT node=%d total=%d splits=%d", i, graph->n_nodes, i_split);
            }
            struct ggml_tensor * node = graph->nodes[i];''',
"pass5 heartbeat")

backend=patch_one(backend,
'''        sched->n_splits = i_split + 1;
    }

    if (sched->debug) {''',
'''        sched->n_splits = i_split + 1;
    }
    bonsai_build84_trace("BUILD86_SPLIT_PASS5_DONE splits=%d", sched->n_splits);

    if (sched->debug) {''',
"pass5 done")

backend=patch_one(backend,
'''    // swap node_backend_ids and leaf _backend_ids with prevs''',
'''    bonsai_build84_trace("BUILD86_SPLIT_COPY_GRAPH_BEGIN splits=%d", sched->n_splits);
    // swap node_backend_ids and leaf _backend_ids with prevs''',
"copy graph")

backend=patch_one(backend,
'''    // add leafs from the original graph
    for (int i = 0; i < graph->n_leafs; i++) {''',
'''    bonsai_build84_trace("BUILD86_SPLIT_COPY_GRAPH_NODES_DONE count=%d", graph_copy->n_nodes);
    // add leafs from the original graph
    for (int i = 0; i < graph->n_leafs; i++) {''',
"copy nodes done")

backend=patch_one(backend,
'''    // set ids for all splits
    for (int i = 0; i < sched->n_splits; ++i) {
        sched->splits[i].graph.uid = ggml_graph_next_uid();
    }
}

static bool ggml_backend_sched_alloc_splits''',
'''    // set ids for all splits
    for (int i = 0; i < sched->n_splits; ++i) {
        sched->splits[i].graph.uid = ggml_graph_next_uid();
    }
    bonsai_build84_trace("BUILD86_SPLIT_DONE splits=%d copied_nodes=%d copied_leafs=%d",
            sched->n_splits, graph_copy->n_nodes, graph_copy->n_leafs);
}

static bool ggml_backend_sched_alloc_splits''',
"split graph complete")

ctx_path.write_text(ctx,encoding="utf-8")
backend_path.write_text(backend,encoding="utf-8")
print("RC1.26 Build86 Prism backend split and fused-probe forensics patch: PASS")
