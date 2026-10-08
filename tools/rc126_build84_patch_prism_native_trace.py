#!/usr/bin/env python3
"""Build 84: add persistent native trace to pinned Prism after Build 83 sharding."""
from pathlib import Path
import sys
if len(sys.argv) != 3:
    raise SystemExit("usage: rc126_build84_patch_prism_native_trace.py <KV_CPP> <CONTEXT_CPP>")
kv_file, context_file = (Path(x) for x in sys.argv[1:])
if kv_file.parent != context_file.parent:
    raise SystemExit("Both files must belong to the same Prism src directory")
header = r'''#pragma once
// Build 84: limited to >=32K experimental context via Swift environment flag.
// Deliberately fsync small records to survive sudden native termination.
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <fcntl.h>
#include <unistd.h>
static inline void bonsai_build84_trace(const char *fmt, ...) {
    const char *path = std::getenv("BONSAI_BUILD84_TRACE_PATH");
    if (!path || !*path) { return; }
    char line[256];
    va_list ap;
    va_start(ap, fmt);
    int n = std::vsnprintf(line, sizeof(line) - 2, fmt, ap);
    va_end(ap);
    if (n <= 0) { return; }
    size_t size = (size_t)n < sizeof(line) - 2 ? (size_t)n : sizeof(line) - 2;
    line[size++] = '\n';
    int fd = ::open(path, O_CREAT | O_APPEND | O_WRONLY, 0600);
    if (fd < 0) { return; }
    size_t done = 0;
    while (done < size) {
        ssize_t count = ::write(fd, line + done, size - done);
        if (count <= 0) { break; }
        done += (size_t)count;
    }
    ::fsync(fd);
    ::close(fd);
}
'''
def once(content, before, after, marker):
    count = content.count(before)
    if count != 1:
        raise SystemExit("Build84 source drift " + marker + ": " + str(count))
    return content.replace(before, after, 1)
kv = kv_file.read_text(encoding="utf-8")
ctx = context_file.read_text(encoding="utf-8")
if "BUILD83_METAL_KV_LAYER_SHARD" not in kv:
    raise SystemExit("Build 83 sharding patch must run first")
kv=once(kv,'#include "llama-kv-cache.h"','#include "llama-kv-cache.h"\n#include "bonsai-build84-trace.h"',"kv include")
ctx=once(ctx,'#include "llama-context.h"','#include "llama-context.h"\n#include "bonsai-build84-trace.h"',"context include")
kv=once(kv,'    const bool is_mla = hparams.is_mla();','    bonsai_build84_trace("BUILD84_KV_INIT_BEGIN ctx=%u offload=%d", kv_size, (int)offload);\n    const bool is_mla = hparams.is_mla();',"KV begin")
kv=once(kv,'        const int32_t build83_ctx_shard = build83_metal_layer_shard ? il : -1;',
'''        const int32_t build83_ctx_shard = build83_metal_layer_shard ? il : -1;
        if (build83_metal_layer_shard) {
            bonsai_build84_trace("BUILD84_KV_SHARD_ROUTE layer=%u shard=%d", il, build83_ctx_shard);
        }''',"KV shard")
kv=once(kv,'    for (auto & [key, ctx] : ctx_map) {','''    bonsai_build84_trace("BUILD84_KV_GROUPS count=%zu", ctx_map.size());
    for (auto & [key, ctx] : ctx_map) {
        bonsai_build84_trace("BUILD84_KV_ALLOC_BEGIN shard=%d", key.shard);''',"KV loop")
kv=once(kv,'        if (!buf) {\n            throw std::runtime_error("failed to allocate buffer for kv cache");\n        }',
'''        if (!buf) {
            bonsai_build84_trace("BUILD84_KV_ALLOC_NULL shard=%d", key.shard);
            throw std::runtime_error("failed to allocate buffer for kv cache");
        }
        bonsai_build84_trace("BUILD84_KV_ALLOC_DONE shard=%d bytes=%zu", key.shard, ggml_backend_buffer_get_size(buf));''',"KV buffer")
kv=once(kv,'        ggml_backend_buffer_clear(buf, 0);\n        ctxs_bufs.emplace_back(std::move(ctx), buf);',
'''        bonsai_build84_trace("BUILD84_KV_CLEAR_BEGIN shard=%d", key.shard);
        ggml_backend_buffer_clear(buf, 0);
        bonsai_build84_trace("BUILD84_KV_CLEAR_DONE shard=%d", key.shard);
        ctxs_bufs.emplace_back(std::move(ctx), buf);''',"KV clear")
kv=once(kv,'    {\n        const size_t memory_size_k = size_k_bytes();',
'    bonsai_build84_trace("BUILD84_KV_INIT_DONE groups=%zu", ctxs_bufs.size());\n    {\n        const size_t memory_size_k = size_k_bytes();',"KV done")
ctx=once(ctx,'        memory.reset(model.create_memory(params_mem, cparams));',
'''        bonsai_build84_trace("BUILD84_CTX_MEMORY_BEGIN n_ctx=%u", cparams.n_ctx);
        memory.reset(model.create_memory(params_mem, cparams));
        bonsai_build84_trace("BUILD84_CTX_MEMORY_DONE n_ctx=%u", cparams.n_ctx);''',"context memory")
ctx=once(ctx,'        sched_reserve();\n\n        if (!cparams.flash_attn)',
'''        bonsai_build84_trace("BUILD84_CTX_SCHED_BEGIN n_ctx=%u", cparams.n_ctx);
        sched_reserve();
        bonsai_build84_trace("BUILD84_CTX_SCHED_DONE n_ctx=%u", cparams.n_ctx);

        if (!cparams.flash_attn)''',"scheduler")
kv_file.write_text(kv,encoding="utf-8")
context_file.write_text(ctx,encoding="utf-8")
(kv_file.parent/"bonsai-build84-trace.h").write_text(header,encoding="utf-8")
print("RC1.26 Build 84 crash-persistent native trace patch: PASS")
