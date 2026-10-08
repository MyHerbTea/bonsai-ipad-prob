#!/usr/bin/env python3
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: rc126_build83_patch_prism_kv_sharding.py <llama-kv-cache.cpp>")

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

old_map = r'''    // define a comparator for the buft -> ctx map to ensure that the order is well-defined:
    struct ggml_backend_buft_comparator {
        bool operator()(const ggml_backend_buffer_type_t & lhs, const ggml_backend_buffer_type_t & rhs) const {
            return strcmp(ggml_backend_buft_name(lhs), ggml_backend_buft_name(rhs)) < 0;
        }
    };
    std::map<ggml_backend_buffer_type_t, ggml_context_ptr, ggml_backend_buft_comparator> ctx_map;

    // create a context for each buffer type
    auto ctx_for_buft = [&](ggml_backend_buffer_type_t buft) -> ggml_context * {
        auto it = ctx_map.find(buft);
        if (it == ctx_map.end()) {
            ggml_init_params params = {
                /*.mem_size   =*/ size_t(2u*(1 + n_stream)*n_layer*ggml_tensor_overhead()),
                /*.mem_buffer =*/ NULL,
                /*.no_alloc   =*/ true,
            };

            ggml_context * ctx = ggml_init(params);
            if (!ctx) {
                return nullptr;
            }

            ctx_map.emplace(buft, ctx);

            return ctx;
        }

        return it->second.get();
    };
'''

new_map = r'''    // Build 83: on iOS Metal, a 32K Qwen3.5 Q4 KV cache must not be
    // packed into one backend allocation. The Metal runtime allocator creates
    // one MTLBuffer per ggml context, while mmap model buffers have separate
    // maxBufferLength-aware splitting. Key the context by (buft, layer shard)
    // only for the targeted long-context Qwen3.5 Metal path.
    struct build83_ctx_key {
        ggml_backend_buffer_type_t buft;
        int32_t shard;
    };
    struct build83_ctx_key_comparator {
        bool operator()(const build83_ctx_key & lhs, const build83_ctx_key & rhs) const {
            const int cmp = strcmp(ggml_backend_buft_name(lhs.buft), ggml_backend_buft_name(rhs.buft));
            if (cmp != 0) {
                return cmp < 0;
            }
            return lhs.shard < rhs.shard;
        }
    };
    std::map<build83_ctx_key, ggml_context_ptr, build83_ctx_key_comparator> ctx_map;

    auto ctx_for_buft = [&](ggml_backend_buffer_type_t buft, int32_t shard) -> ggml_context * {
        const build83_ctx_key key = { buft, shard };
        auto it = ctx_map.find(key);
        if (it == ctx_map.end()) {
            ggml_init_params params = {
                /*.mem_size   =*/ size_t(2u*(1 + n_stream)*n_layer*ggml_tensor_overhead()),
                /*.mem_buffer =*/ NULL,
                /*.no_alloc   =*/ true,
            };

            ggml_context * ctx = ggml_init(params);
            if (!ctx) {
                return nullptr;
            }

            ctx_map.emplace(key, ctx);

            return ctx;
        }

        return it->second.get();
    };
'''

old_layer = r'''        const char * dev_name = "CPU";

        ggml_backend_buffer_type_t buft = ggml_backend_cpu_buffer_type();

        if (offload) {
            auto * dev = model.dev_layer(il);
            buft = ggml_backend_dev_buffer_type(dev);

            dev_name = ggml_backend_dev_name(dev);
        }

        LLAMA_LOG_DEBUG("%s: layer %3d: dev = %s\n", __func__, il, dev_name);

        ggml_context * ctx = ctx_for_buft(buft);
        if (!ctx) {
            throw std::runtime_error("failed to create ggml context for kv cache");
        }
'''

new_layer = r'''        const char * dev_name = "CPU";

        ggml_backend_buffer_type_t buft = ggml_backend_cpu_buffer_type();

        if (offload) {
            auto * dev = model.dev_layer(il);
            buft = ggml_backend_dev_buffer_type(dev);

            dev_name = ggml_backend_dev_name(dev);
        }

        const bool build83_metal_layer_shard =
            offload &&
            kv_size >= 32768 &&
            (model.arch == LLM_ARCH_QWEN35 || model.arch == LLM_ARCH_QWEN35MOE) &&
            dev_name != nullptr &&
            strncmp(dev_name, "MTL", 3) == 0;
        const int32_t build83_ctx_shard = build83_metal_layer_shard ? il : -1;

        LLAMA_LOG_DEBUG("%s: layer %3d: dev = %s\n", __func__, il, dev_name);
        if (build83_metal_layer_shard) {
            LLAMA_LOG_INFO("%s: BUILD83_METAL_KV_LAYER_SHARD layer=%d kv_size=%u\n", __func__, il, kv_size);
        }

        ggml_context * ctx = ctx_for_buft(buft, build83_ctx_shard);
        if (!ctx) {
            throw std::runtime_error("failed to create ggml context for kv cache");
        }
'''

old_alloc = r'''    // allocate tensors and initialize the buffers to avoid NaNs in the padding
    for (auto & [buft, ctx] : ctx_map) {
        ggml_backend_buffer_t buf;
        if (hparams.no_alloc) {
            buf = ggml_backend_buft_alloc_buffer(buft, /*size =*/ 0); // dummy buffer
            for (ggml_tensor * t = ggml_get_first_tensor(ctx.get()); t != nullptr; t = ggml_get_next_tensor(ctx.get(), t)) {
                t->buffer = buf; // set dummy buffer for KV cache so that the backend scheduler won't try to allocate it
            }
        } else {
            buf = ggml_backend_alloc_ctx_tensors_from_buft(ctx.get(), buft); // real buffer
        }
        if (!buf) {
            throw std::runtime_error("failed to allocate buffer for kv cache");
        }

        LLAMA_LOG_INFO("%s: %10s KV buffer size = %8.2f MiB\n", __func__, ggml_backend_buffer_name(buf), ggml_backend_buffer_get_size(buf)/1024.0/1024.0);

        ggml_backend_buffer_clear(buf, 0);
        ctxs_bufs.emplace_back(std::move(ctx), buf);
    }
'''

new_alloc = r'''    // allocate tensors and initialize the buffers to avoid NaNs in the padding
    for (auto & [key, ctx] : ctx_map) {
        ggml_backend_buffer_type_t buft = key.buft;
        ggml_backend_buffer_t buf;
        if (hparams.no_alloc) {
            buf = ggml_backend_buft_alloc_buffer(buft, /*size =*/ 0); // dummy buffer
            for (ggml_tensor * t = ggml_get_first_tensor(ctx.get()); t != nullptr; t = ggml_get_next_tensor(ctx.get(), t)) {
                t->buffer = buf; // set dummy buffer for KV cache so that the backend scheduler won't try to allocate it
            }
        } else {
            buf = ggml_backend_alloc_ctx_tensors_from_buft(ctx.get(), buft); // real buffer
        }
        if (!buf) {
            throw std::runtime_error("failed to allocate buffer for kv cache");
        }

        LLAMA_LOG_INFO("%s: %10s KV buffer size = %8.2f MiB (build83 shard=%d)\n",
                __func__, ggml_backend_buffer_name(buf), ggml_backend_buffer_get_size(buf)/1024.0/1024.0, key.shard);

        ggml_backend_buffer_clear(buf, 0);
        ctxs_bufs.emplace_back(std::move(ctx), buf);
    }
'''

for name, old, new in [
    ("ctx-map", old_map, new_map),
    ("layer-routing", old_layer, new_layer),
    ("allocation-loop", old_alloc, new_alloc),
]:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"Build83 patch refused: {name} expected exactly once, found {count}")
    text = text.replace(old, new, 1)

for marker in [
    "BUILD83_METAL_KV_LAYER_SHARD",
    "build83_ctx_key",
    "kv_size >= 32768",
    "LLM_ARCH_QWEN35",
    'strncmp(dev_name, "MTL", 3) == 0',
]:
    if marker not in text:
        raise SystemExit(f"Build83 patch verification failed: {marker}")

path.write_text(text, encoding="utf-8")
print("RC1.26 Build 83 Prism Metal KV layer sharding patch: PASS")
