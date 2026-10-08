#!/usr/bin/env python3
"""Build88: recover oversized scheduler metadata context using lazy anonymous mmap.

Patches pinned Prism after Build83/84/85/86/87 in the iOS workflow.
Only activates if a >=32K attempt (native trace latch present) experiences
NULL from the original malloc. All 16K and successful malloc paths unchanged.
On double failure, release constructor allocations and return NULL, allowing
llama_context to throw instead of invoking ggml_init with a NULL large buffer.
"""
from pathlib import Path
import sys
if len(sys.argv) != 3:
    raise SystemExit("usage: rc126_build88_patch_prism_mmap_recovery.py <backend.cpp> <context.cpp>")
backend_path, context_path = (Path(x) for x in sys.argv[1:])
backend = backend_path.read_text(encoding="utf-8")
ctx = context_path.read_text(encoding="utf-8")
if 'BUILD87_SCHED_BUFFER_ALLOC' not in backend or 'BUILD85_BACKEND_SCHED_NEW_DONE' not in ctx:
    raise SystemExit("Build88 requires Build87 and Build85 patches first")
def once(data, old, new, label):
    c = data.count(old)
    if c != 1:
        raise SystemExit(f"Build88 source drift at {label}: wanted 1, found {c}")
    return data.replace(old, new, 1)

backend = once(backend,
'#include "ggml-backend-impl.h"',
'''#include "ggml-backend-impl.h"
#if defined(__APPLE__)
#include <sys/mman.h>
#include <cerrno>
#endif''',
"mmap includes")
backend = once(backend,
'''    char * context_buffer;
    size_t context_buffer_size;

    bool op_offload;''',
'''    char * context_buffer;
    size_t context_buffer_size;
    bool context_buffer_mmap;

    bool op_offload;''',
"scheduler ownership flag")
backend = once(backend,
'''    bonsai_build84_trace("BUILD87_SCHED_BUFFER_ALLOC bytes=%zu buffer_nonnull=%d",
            sched->context_buffer_size, (int)(sched->context_buffer != NULL));

    const int initial_splits_capacity = 16;''',
'''    bonsai_build84_trace("BUILD87_SCHED_BUFFER_ALLOC bytes=%zu buffer_nonnull=%d",
            sched->context_buffer_size, (int)(sched->context_buffer != NULL));
#if defined(__APPLE__)
    // 32K-only recovery: anonymous mmap reserves a contiguous virtual range
    // without eagerly committing the entire worst-case graph metadata pool.
    // Graph scheduler semantics and maximum capacity are unchanged.
    if (sched->context_buffer == NULL && std::getenv("BONSAI_BUILD84_TRACE_PATH") != NULL) {
        bonsai_build84_trace("BUILD88_MMAP_BEGIN bytes=%zu", sched->context_buffer_size);
        void * mapped = mmap(NULL, sched->context_buffer_size,
                            PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
        if (mapped != MAP_FAILED) {
            sched->context_buffer = (char *) mapped;
            sched->context_buffer_mmap = true;
            bonsai_build84_trace("BUILD88_MMAP_SUCCESS bytes=%zu", sched->context_buffer_size);
        } else {
            bonsai_build84_trace("BUILD88_MMAP_FAILURE errno=%d", errno);
        }
        if (sched->context_buffer == NULL) {
            // Never permit ggml_init() to silently retry an equally large
            // allocation after malloc AND mmap failed.
            bonsai_build84_trace("BUILD88_SCHED_ALLOC_EXHAUSTED graceful_return_null=1");
            ggml_hash_set_free(&sched->hash_set);
            free(sched->hv_tensor_backend_ids);
            free(sched->hv_tensor_copies);
            free(sched->node_backend_ids);
            free(sched->leaf_backend_ids);
            free(sched->prev_node_backend_ids);
            free(sched->prev_leaf_backend_ids);
            free(sched);
            return NULL;
        }
    }
#endif

    const int initial_splits_capacity = 16;''',
"mmap fallback and guarded failure")
backend = once(backend,
'''    free(sched->context_buffer);
    free(sched->graph.nodes);''',
'''#if defined(__APPLE__)
    if (sched->context_buffer_mmap) {
        bonsai_build84_trace("BUILD88_MMAP_RELEASE_BEGIN bytes=%zu", sched->context_buffer_size);
        munmap(sched->context_buffer, sched->context_buffer_size);
        bonsai_build84_trace("BUILD88_MMAP_RELEASE_DONE");
    } else
#endif
    {
        free(sched->context_buffer);
    }
    free(sched->graph.nodes);''',
"owned mmap cleanup")
ctx = once(ctx,
'''    bonsai_build84_trace("BUILD85_BACKEND_SCHED_NEW_DONE");

    llama_memory_context_ptr mctx;''',
'''    bonsai_build84_trace("BUILD85_BACKEND_SCHED_NEW_DONE");
    if (!sched) {
        bonsai_build84_trace("BUILD88_SCHED_NEW_NULL_CTX_ABORT_PREVENTED");
        throw std::runtime_error("Build88: graph scheduler buffer malloc and mmap both failed");
    }

    llama_memory_context_ptr mctx;''',
"llama graceful scheduler null")
backend_path.write_text(backend,encoding="utf-8")
context_path.write_text(ctx,encoding="utf-8")
print("RC1.26 Build88 32K scheduler mmap recovery native patch: PASS")
