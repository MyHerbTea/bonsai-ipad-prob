#!/usr/bin/env python3
"""RC1.26 Build87: instrument the scheduler's 525 MiB GGML context buffer lifecycle.

Run after Build83/84/85/86 on Prism pinned commit adfffbe41. This is
evidence-only instrumentation; the GGML and inference control flow is unchanged.
"""
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: rc126_build87_patch_prism_sched_context.py <ggml-backend.cpp>")
path=Path(sys.argv[1])
code=path.read_text(encoding="utf-8")
if "BUILD86_SPLIT_ENTER" not in code:
    raise SystemExit("Build87 requires the Build86 backend split patch first")
if "BUILD87_SPLIT_INIT_BEGIN" in code:
    raise SystemExit("Build87 patch already applied")

def exact(old, new, stage):
    global code
    count=code.count(old)
    if count != 1:
        raise SystemExit(f"Build87 Prism source drift at {stage}: expected 1, found {count}")
    code=code.replace(old,new,1)

exact(
'''    sched->context_buffer = (char *) malloc(sched->context_buffer_size);

    const int initial_splits_capacity = 16;''',
'''    sched->context_buffer = (char *) malloc(sched->context_buffer_size);
    bonsai_build84_trace("BUILD87_SCHED_BUFFER_ALLOC bytes=%zu buffer_nonnull=%d",
            sched->context_buffer_size, (int)(sched->context_buffer != NULL));

    const int initial_splits_capacity = 16;''',
"constructor buffer allocation")

exact(
'''    // reset splits
    sched->n_splits = 0;
    sched->n_graph_inputs = 0;
    sched->is_reset = false;

    struct ggml_init_params params = {''',
'''    bonsai_build84_trace("BUILD87_SPLIT_INIT_BEGIN");
    // reset splits
    sched->n_splits = 0;
    sched->n_graph_inputs = 0;
    sched->is_reset = false;
    bonsai_build84_trace("BUILD87_SPLIT_RESET_DONE");

    struct ggml_init_params params = {''',
"reset stage")

exact(
'''    ggml_free(sched->ctx);

    sched->ctx = ggml_init(params);
    if (sched->ctx == NULL) {
        GGML_ABORT("%s: failed to initialize context\\n", __func__);
    }

    graph->uid = ggml_graph_next_uid();''',
'''    bonsai_build84_trace("BUILD87_SPLIT_CTX_FREE_BEGIN old_ctx_nonnull=%d", (int)(sched->ctx != NULL));
    ggml_free(sched->ctx);
    bonsai_build84_trace("BUILD87_SPLIT_CTX_FREE_DONE");
    bonsai_build84_trace("BUILD87_SPLIT_GGML_INIT_BEGIN bytes=%zu external_buffer_nonnull=%d",
            params.mem_size, (int)(params.mem_buffer != NULL));
    sched->ctx = ggml_init(params);
    bonsai_build84_trace("BUILD87_SPLIT_GGML_INIT_DONE ctx_nonnull=%d", (int)(sched->ctx != NULL));
    if (sched->ctx == NULL) {
        bonsai_build84_trace("BUILD87_SPLIT_GGML_INIT_NULL");
        GGML_ABORT("%s: failed to initialize context\\n", __func__);
    }

    bonsai_build84_trace("BUILD87_SPLIT_UID_BEGIN");
    graph->uid = ggml_graph_next_uid();
    bonsai_build84_trace("BUILD87_SPLIT_UID_DONE uid=%zu", (size_t)graph->uid);''',
"ggml_free/ggml_init/graph uid")

path.write_text(code,encoding="utf-8")
print("RC1.26 Build87 scheduler context initialization instrumentation: PASS")
