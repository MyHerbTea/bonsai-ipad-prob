#!/usr/bin/env python3
"""Build89: replace 32K scheduler's failed oversized malloc with safe compact budget.

Pinned Prism adfffbe41, after Build88. Only on failed original malloc and
when the experimental >=32K trace environment variable is present.
"""
from pathlib import Path
import sys
if len(sys.argv) != 2:
    raise SystemExit("usage: rc126_build89_patch_prism_compact_scheduler.py <ggml-backend.cpp>")
path=Path(sys.argv[1])
s=path.read_text(encoding="utf-8")
if "BUILD88_MMAP_BEGIN" not in s or "BUILD87_SCHED_BUFFER_ALLOC" not in s:
    raise SystemExit("Build89 needs Build88")
def exact(a,b,label):
    global s
    n=s.count(a)
    if n != 1:
        raise SystemExit(f"Build89 native source drift {label}: {n} matches")
    s=s.replace(a,b,1)
exact(
'''    bonsai_build84_trace("BUILD87_SCHED_BUFFER_ALLOC bytes=%zu buffer_nonnull=%d",
            sched->context_buffer_size, (int)(sched->context_buffer != NULL));
#if defined(__APPLE__)''',
'''    bonsai_build84_trace("BUILD87_SCHED_BUFFER_ALLOC bytes=%zu buffer_nonnull=%d",
            sched->context_buffer_size, (int)(sched->context_buffer != NULL));
#if defined(__APPLE__)
    if (sched->context_buffer == NULL && getenv("BONSAI_BUILD84_TRACE_PATH") != NULL) {
        // One identity may be copied to each target backend/copy slot and
        // produce one dependency view per cross-backend input. Derive from
        // hash capacity, not the observed first probe graph node count.
        const size_t hash_entries = sched->hash_set.size;
        const size_t objects_per_entry = 2u * (size_t) sched->n_backends * (size_t) sched->n_copies + 2u;
        const size_t object_bytes = ggml_tensor_overhead();
        const size_t graph_bytes = ggml_graph_overhead_custom(graph_size, false);
        const size_t margin_bytes = 1024u * 1024u;
        const size_t size_limit = (size_t) -1;
        const size_t unit_bytes = objects_per_entry * object_bytes;
        if (unit_bytes != 0 && graph_bytes <= size_limit - margin_bytes &&
            hash_entries <= (size_limit - margin_bytes - graph_bytes) / unit_bytes) {
            const size_t compact_bytes = hash_entries * unit_bytes + graph_bytes + margin_bytes;
            bonsai_build84_trace("BUILD89_COMPACT_BUDGET old_bytes=%zu new_bytes=%zu hash_entries=%zu backends=%d copies=%d objects_per_id=%zu",
                    sched->context_buffer_size, compact_bytes, hash_entries, sched->n_backends, sched->n_copies, objects_per_entry);
            sched->context_buffer_size = compact_bytes;
            sched->context_buffer = (char *) malloc(compact_bytes);
            if (sched->context_buffer != NULL) {
                bonsai_build84_trace("BUILD89_COMPACT_ALLOC_SUCCESS bytes=%zu", compact_bytes);
            } else {
                bonsai_build84_trace("BUILD89_COMPACT_ALLOC_FAILURE bytes=%zu", compact_bytes);
            }
        } else {
            bonsai_build84_trace("BUILD89_COMPACT_BUDGET_OVERFLOW");
        }
    }
#endif
#if defined(__APPLE__)''',
"bounded fallback")
exact(
'''    bonsai_build84_trace("BUILD86_SPLIT_DONE splits=%d copied_nodes=%d copied_leafs=%d",
            sched->n_splits, graph_copy->n_nodes, graph_copy->n_leafs);''',
'''    bonsai_build84_trace("BUILD86_SPLIT_DONE splits=%d copied_nodes=%d copied_leafs=%d",
            sched->n_splits, graph_copy->n_nodes, graph_copy->n_leafs);
    bonsai_build84_trace("BUILD89_META_USED bytes=%zu capacity=%zu",
            ggml_used_mem(sched->ctx), sched->context_buffer_size);''',
"usage telemetry")
path.write_text(s,encoding="utf-8")
print("RC1.26 Build89 bounded GGML scheduler metadata patch: PASS")
