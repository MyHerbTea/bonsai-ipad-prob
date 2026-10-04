#include "StagedVisionBridge.h"

#include <llama/llama.h>
#include <llama/mtmd.h>
#include <llama/mtmd-helper.h>
#include <llama/gguf.h>

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#include <limits>
#include <mutex>
#include <sys/stat.h>
#include <unistd.h>

namespace {

enum class PacketKind {
    Text,
    Image,
};

struct PacketChunk {
    PacketKind kind = PacketKind::Text;
    std::vector<llama_token> tokens;
    std::vector<float> embeddings;
    std::vector<llama_pos> positions;
    llama_pos n_pos = 0;
    bool mrope = false;
    bool non_causal = false;
};

static void write_stage(const char * path, const char * stage) {
    if (path == nullptr || path[0] == '\0' || stage == nullptr) {
        return;
    }

    FILE * f = std::fopen(path, "w");
    if (f == nullptr) {
        return;
    }

    std::fprintf(f, "%s\n", stage);
    std::fflush(f);
    fsync(fileno(f));
    std::fclose(f);
}

static void set_error(
    char * out_error,
    size_t cap,
    const std::string & message
) {
    if (out_error == nullptr || cap == 0) {
        return;
    }
    std::snprintf(out_error, cap, "%s", message.c_str());
}

static double elapsed_ms(
    std::chrono::steady_clock::time_point start,
    std::chrono::steady_clock::time_point end
) {
    return std::chrono::duration<double, std::milli>(end - start).count();
}

static int32_t read_projection_dim(const char * mmproj_path) {
    gguf_init_params gp {
        true,
        nullptr,
    };

    gguf_context * gg = gguf_init_from_file(mmproj_path, gp);
    if (gg == nullptr) {
        return 0;
    }

    const int64_t key = gguf_find_key(
        gg,
        "clip.vision.projection_dim"
    );

    int32_t dim = 0;
    if (key >= 0) {
        dim = static_cast<int32_t>(
            gguf_get_val_u32(gg, key)
        );
    }

    gguf_free(gg);
    return dim;
}

struct CachedImagePacket {
    int32_t projection_dim = 0;
    int32_t image_max_tokens = 0;
    int32_t n_tokens = 0;
    llama_pos n_pos = 0;
    bool mrope = false;
    bool non_causal = false;
    std::vector<float> embeddings;
    std::vector<llama_pos> relative_positions;
};

static constexpr char kVisionCacheMagic[8] = {
    'B', 'V', 'C', 'A', 'C', 'H', 'E', '1'
};
static constexpr uint32_t kVisionCacheVersion = 1;

static std::mutex g_staged_mutex;
static llama_model * g_resident_model = nullptr;
static std::string g_resident_model_path;
static int32_t g_resident_gpu_layers = -1;
static llama_context * g_resident_ctx = nullptr;
static std::string g_resident_session_key;
static llama_pos g_resident_n_past = 0;
static int32_t g_resident_n_ctx = 0;
static int32_t g_resident_n_batch = 0;
static int32_t g_resident_n_ubatch = 0;
static int32_t g_resident_accelerated_mode = -1;

static void release_resident_context_locked() {
    if (g_resident_ctx != nullptr) {
        llama_free(g_resident_ctx);
        g_resident_ctx = nullptr;
    }
    g_resident_session_key.clear();
    g_resident_n_past = 0;
    g_resident_n_ctx = 0;
    g_resident_n_batch = 0;
    g_resident_n_ubatch = 0;
    g_resident_accelerated_mode = -1;
}

static void release_resident_model_locked() {
    release_resident_context_locked();
    if (g_resident_model != nullptr) {
        llama_model_free(g_resident_model);
        g_resident_model = nullptr;
    }
    g_resident_model_path.clear();
    g_resident_gpu_layers = -1;
}

static bool resident_context_matches(
    const char * session_key,
    int32_t n_ctx,
    int32_t n_batch,
    int32_t n_ubatch,
    int32_t accelerated_mode
) {
    return g_resident_ctx != nullptr &&
        session_key != nullptr && session_key[0] != '\0' &&
        g_resident_session_key == session_key &&
        g_resident_n_ctx == n_ctx &&
        g_resident_n_batch == n_batch &&
        g_resident_n_ubatch == n_ubatch &&
        g_resident_accelerated_mode == accelerated_mode;
}

static bool resident_model_matches(
    const char * model_path,
    int32_t gpu_layers
) {
    return
        g_resident_model != nullptr &&
        model_path != nullptr &&
        g_resident_model_path == model_path &&
        g_resident_gpu_layers == gpu_layers;
}


template <typename T>
static bool write_value(FILE * f, const T & value) {
    return std::fwrite(&value, sizeof(T), 1, f) == 1;
}

template <typename T>
static bool read_value(FILE * f, T & value) {
    return std::fread(&value, sizeof(T), 1, f) == 1;
}

static uint64_t file_size_bytes(const char * path) {
    if (path == nullptr || path[0] == '\0') {
        return 0;
    }

    struct stat st {};
    if (stat(path, &st) != 0 || st.st_size < 0) {
        return 0;
    }
    return static_cast<uint64_t>(st.st_size);
}

static bool save_cached_image(
    const char * path,
    const CachedImagePacket & packet
) {
    if (
        path == nullptr ||
        path[0] == '\0' ||
        packet.projection_dim <= 0 ||
        packet.n_tokens <= 0 ||
        packet.n_pos <= 0
    ) {
        return false;
    }

    const uint32_t flags =
        (packet.mrope ? 1u : 0u) |
        (packet.non_causal ? 2u : 0u);
    const uint64_t embedding_count =
        static_cast<uint64_t>(packet.embeddings.size());
    const uint64_t position_count =
        static_cast<uint64_t>(packet.relative_positions.size());

    const uint64_t expected_embeddings =
        static_cast<uint64_t>(packet.n_tokens) *
        static_cast<uint64_t>(packet.projection_dim);
    const uint64_t expected_positions =
        static_cast<uint64_t>(packet.n_tokens) *
        static_cast<uint64_t>(packet.mrope ? 4 : 1);

    if (
        embedding_count != expected_embeddings ||
        position_count != expected_positions
    ) {
        return false;
    }

    FILE * f = std::fopen(path, "wb");
    if (f == nullptr) {
        return false;
    }

    bool ok =
        std::fwrite(kVisionCacheMagic, 1, sizeof(kVisionCacheMagic), f)
            == sizeof(kVisionCacheMagic) &&
        write_value(f, kVisionCacheVersion) &&
        write_value(f, packet.image_max_tokens) &&
        write_value(f, packet.projection_dim) &&
        write_value(f, packet.n_tokens) &&
        write_value(f, packet.n_pos) &&
        write_value(f, flags) &&
        write_value(f, embedding_count) &&
        write_value(f, position_count);

    if (ok && embedding_count > 0) {
        ok = std::fwrite(
            packet.embeddings.data(),
            sizeof(float),
            static_cast<size_t>(embedding_count),
            f
        ) == static_cast<size_t>(embedding_count);
    }

    if (ok && position_count > 0) {
        ok = std::fwrite(
            packet.relative_positions.data(),
            sizeof(llama_pos),
            static_cast<size_t>(position_count),
            f
        ) == static_cast<size_t>(position_count);
    }

    if (ok) {
        std::fflush(f);
        fsync(fileno(f));
    }

    std::fclose(f);

    if (!ok) {
        std::remove(path);
    }

    return ok;
}

static bool load_cached_image(
    const char * path,
    int32_t expected_image_max_tokens,
    CachedImagePacket & packet
) {
    if (path == nullptr || path[0] == '\0') {
        return false;
    }

    FILE * f = std::fopen(path, "rb");
    if (f == nullptr) {
        return false;
    }

    char magic[8] = {};
    uint32_t version = 0;
    uint32_t flags = 0;
    uint64_t embedding_count = 0;
    uint64_t position_count = 0;

    bool ok =
        std::fread(magic, 1, sizeof(magic), f) == sizeof(magic) &&
        std::memcmp(magic, kVisionCacheMagic, sizeof(magic)) == 0 &&
        read_value(f, version) &&
        version == kVisionCacheVersion &&
        read_value(f, packet.image_max_tokens) &&
        packet.image_max_tokens == expected_image_max_tokens &&
        read_value(f, packet.projection_dim) &&
        read_value(f, packet.n_tokens) &&
        read_value(f, packet.n_pos) &&
        read_value(f, flags) &&
        read_value(f, embedding_count) &&
        read_value(f, position_count);

    if (ok) {
        packet.mrope = (flags & 1u) != 0;
        packet.non_causal = (flags & 2u) != 0;

        const bool shape_ok =
            packet.projection_dim > 0 &&
            packet.projection_dim <= 65536 &&
            packet.n_tokens > 0 &&
            packet.n_tokens <= 8192 &&
            packet.n_pos > 0 &&
            packet.n_pos <= 8192 &&
            embedding_count ==
                static_cast<uint64_t>(packet.n_tokens) *
                static_cast<uint64_t>(packet.projection_dim) &&
            position_count ==
                static_cast<uint64_t>(packet.n_tokens) *
                static_cast<uint64_t>(packet.mrope ? 4 : 1) &&
            embedding_count <=
                static_cast<uint64_t>(8192) * 65536ull;

        ok = shape_ok;
    }

    if (ok) {
        packet.embeddings.resize(
            static_cast<size_t>(embedding_count)
        );
        packet.relative_positions.resize(
            static_cast<size_t>(position_count)
        );

        ok = std::fread(
            packet.embeddings.data(),
            sizeof(float),
            static_cast<size_t>(embedding_count),
            f
        ) == static_cast<size_t>(embedding_count);
    }

    if (ok) {
        ok = std::fread(
            packet.relative_positions.data(),
            sizeof(llama_pos),
            static_cast<size_t>(position_count),
            f
        ) == static_cast<size_t>(position_count);
    }

    std::fclose(f);
    return ok;
}

static bool tokenize_text_exact(
    const llama_vocab * vocab,
    const std::string & text,
    bool parse_special,
    std::vector<llama_token> & out
) {
    if (vocab == nullptr) {
        return false;
    }

    const int32_t initial_cap = static_cast<int32_t>(
        std::min<size_t>(
            static_cast<size_t>(std::numeric_limits<int32_t>::max() - 2),
            text.size() + 2
        )
    );

    out.resize(static_cast<size_t>(std::max(2, initial_cap)));
    int32_t n = llama_tokenize(
        vocab,
        text.data(),
        static_cast<int32_t>(text.size()),
        out.data(),
        static_cast<int32_t>(out.size()),
        false,
        parse_special
    );

    if (n == std::numeric_limits<int32_t>::min()) {
        out.clear();
        return false;
    }

    if (n < 0) {
        out.resize(static_cast<size_t>(-n));
        n = llama_tokenize(
            vocab,
            text.data(),
            static_cast<int32_t>(text.size()),
            out.data(),
            static_cast<int32_t>(out.size()),
            false,
            parse_special
        );
    }

    if (n < 0) {
        out.clear();
        return false;
    }

    out.resize(static_cast<size_t>(n));
    return true;
}

static bool build_packet_from_cached_image(
    const llama_model * bootstrap,
    const char * question,
    const CachedImagePacket & cached,
    std::vector<PacketChunk> & packet,
    llama_pos & stage_a_pos,
    int32_t & prompt_tokens
) {
    if (bootstrap == nullptr || question == nullptr) {
        return false;
    }

    const llama_vocab * vocab = llama_model_get_vocab(bootstrap);
    if (vocab == nullptr) {
        return false;
    }

    // Bonsai 2 follows the Qwen-VL boundary tokens used by Prism mtmd.
    const std::string prefix =
        "<|im_start|>system\n"
        "You are a helpful assistant.<|im_end|>\n"
        "<|im_start|>user\n"
        "<|vision_start|>";
    const std::string suffix =
        std::string("<|vision_end|>\n") +
        question +
        "<|im_end|>\n"
        "<|im_start|>assistant\n";

    PacketChunk prefix_chunk;
    prefix_chunk.kind = PacketKind::Text;
    if (!tokenize_text_exact(
        vocab,
        prefix,
        true,
        prefix_chunk.tokens
    )) {
        return false;
    }

    if (llama_vocab_get_add_bos(vocab)) {
        prefix_chunk.tokens.insert(
            prefix_chunk.tokens.begin(),
            llama_vocab_bos(vocab)
        );
    }

    prefix_chunk.n_pos = static_cast<llama_pos>(
        prefix_chunk.tokens.size()
    );

    PacketChunk image_chunk;
    image_chunk.kind = PacketKind::Image;
    image_chunk.embeddings = cached.embeddings;
    image_chunk.n_pos = cached.n_pos;
    image_chunk.mrope = cached.mrope;
    image_chunk.non_causal = cached.non_causal;
    image_chunk.positions = cached.relative_positions;

    const llama_pos image_pos_0 = prefix_chunk.n_pos;
    if (image_chunk.mrope) {
        const size_t n = static_cast<size_t>(cached.n_tokens);
        if (image_chunk.positions.size() != n * 4) {
            return false;
        }

        // mtmd M-RoPE for Qwen adds pos_0 to t/x/y, z stays 0.
        for (size_t i = 0; i < n; ++i) {
            image_chunk.positions[i] += image_pos_0;
            image_chunk.positions[i + n] += image_pos_0;
            image_chunk.positions[i + n * 2] += image_pos_0;
        }
    } else {
        for (auto & p : image_chunk.positions) {
            p += image_pos_0;
        }
    }

    PacketChunk suffix_chunk;
    suffix_chunk.kind = PacketKind::Text;
    if (!tokenize_text_exact(
        vocab,
        suffix,
        true,
        suffix_chunk.tokens
    )) {
        return false;
    }

    if (llama_vocab_get_add_eos(vocab)) {
        suffix_chunk.tokens.push_back(
            llama_vocab_eos(vocab)
        );
    }

    suffix_chunk.n_pos = static_cast<llama_pos>(
        suffix_chunk.tokens.size()
    );

    packet.clear();
    packet.reserve(3);
    packet.push_back(std::move(prefix_chunk));
    packet.push_back(std::move(image_chunk));
    packet.push_back(std::move(suffix_chunk));

    stage_a_pos =
        packet[0].n_pos +
        packet[1].n_pos +
        packet[2].n_pos;

    prompt_tokens =
        static_cast<int32_t>(packet[0].tokens.size()) +
        cached.n_tokens +
        static_cast<int32_t>(packet[2].tokens.size());

    return true;
}

static bool packets_equal(
    const std::vector<PacketChunk> & a,
    const std::vector<PacketChunk> & b
) {
    if (a.size() != b.size()) {
        return false;
    }

    for (size_t i = 0; i < a.size(); ++i) {
        if (
            a[i].kind != b[i].kind ||
            a[i].tokens != b[i].tokens ||
            a[i].embeddings != b[i].embeddings ||
            a[i].positions != b[i].positions ||
            a[i].n_pos != b[i].n_pos ||
            a[i].mrope != b[i].mrope ||
            a[i].non_causal != b[i].non_causal
        ) {
            return false;
        }
    }

    return true;
}

static std::string token_piece(
    const llama_vocab * vocab,
    llama_token token
) {
    std::vector<char> buf(64);
    int32_t n = llama_token_to_piece(
        vocab,
        token,
        buf.data(),
        static_cast<int32_t>(buf.size()),
        0,
        true
    );

    if (n < 0) {
        buf.resize(static_cast<size_t>(-n));
        n = llama_token_to_piece(
            vocab,
            token,
            buf.data(),
            static_cast<int32_t>(buf.size()),
            0,
            true
        );
    }

    if (n <= 0) {
        return {};
    }

    return std::string(buf.data(), static_cast<size_t>(n));
}

static int32_t decode_text_chunk(
    llama_context * ctx,
    const PacketChunk & chunk,
    llama_pos & n_past,
    int32_t n_batch,
    bool logits_last
) {
    size_t offset = 0;

    while (offset < chunk.tokens.size()) {
        const int32_t count = static_cast<int32_t>(
            std::min<size_t>(
                static_cast<size_t>(n_batch),
                chunk.tokens.size() - offset
            )
        );

        llama_batch batch = llama_batch_init(count, 0, 1);
        batch.n_tokens = 0;

        for (int32_t i = 0; i < count; ++i) {
            const int32_t j = batch.n_tokens;
            const size_t absolute = offset + static_cast<size_t>(i);
            const bool last =
                logits_last &&
                absolute + 1 == chunk.tokens.size();

            batch.token[j] = chunk.tokens[absolute];
            batch.pos[j] = n_past++;
            batch.n_seq_id[j] = 1;
            batch.seq_id[j][0] = 0;
            batch.logits[j] = last ? 1 : 0;
            batch.n_tokens += 1;
        }

        const int32_t rc = llama_decode(ctx, batch);
        llama_batch_free(batch);
        if (rc != 0) {
            return rc;
        }

        offset += static_cast<size_t>(count);
    }

    return 0;
}

static int32_t decode_image_chunk(
    llama_context * ctx,
    const PacketChunk & chunk,
    int32_t n_embd,
    llama_pos & n_past,
    int32_t n_batch,
    bool logits_last
) {
    const int32_t total = static_cast<int32_t>(
        chunk.embeddings.size() / static_cast<size_t>(n_embd)
    );

    if (total <= 0) {
        return -100;
    }

    if (chunk.non_causal) {
        llama_set_causal_attn(ctx, false);
    }

    int32_t offset = 0;
    while (offset < total) {
        const int32_t count = std::min(n_batch, total - offset);
        const int32_t dims = chunk.mrope ? 4 : 1;

        std::vector<llama_pos> pos(
            static_cast<size_t>(count) * static_cast<size_t>(dims)
        );

        if (chunk.mrope) {
            for (int32_t d = 0; d < 4; ++d) {
                const size_t src =
                    static_cast<size_t>(d) * static_cast<size_t>(total)
                    + static_cast<size_t>(offset);
                const size_t dst =
                    static_cast<size_t>(d) * static_cast<size_t>(count);

                std::copy_n(
                    chunk.positions.data() + src,
                    count,
                    pos.data() + dst
                );
            }
        } else {
            std::copy_n(
                chunk.positions.data() + offset,
                count,
                pos.data()
            );
        }

        std::vector<int32_t> n_seq_id(
            static_cast<size_t>(count),
            1
        );
        std::vector<llama_seq_id> seq0(1, 0);
        std::vector<llama_seq_id *> seq_ids(
            static_cast<size_t>(count),
            seq0.data()
        );
        std::vector<int8_t> logits(
            static_cast<size_t>(count),
            0
        );

        if (logits_last && offset + count == total) {
            logits.back() = 1;
        }

        llama_batch batch {
            count,
            nullptr,
            const_cast<float *>(
                chunk.embeddings.data()
                    + static_cast<size_t>(offset)
                    * static_cast<size_t>(n_embd)
            ),
            pos.data(),
            n_seq_id.data(),
            seq_ids.data(),
            logits.data(),
        };

        const int32_t rc = llama_decode(ctx, batch);
        if (rc != 0) {
            if (chunk.non_causal) {
                llama_set_causal_attn(ctx, true);
            }
            return rc;
        }

        offset += count;
    }

    if (chunk.non_causal) {
        llama_set_causal_attn(ctx, true);
    }

    n_past += chunk.n_pos;
    return 0;
}

} // namespace


int32_t BonsaiVisionCacheIsValid(
    const char * cache_path,
    int32_t image_max_tokens
) {
    std::lock_guard<std::mutex> lock(g_staged_mutex);
    CachedImagePacket packet;
    return load_cached_image(
        cache_path,
        image_max_tokens,
        packet
    ) ? 1 : 0;
}

BonsaiVisionCacheResult BonsaiWriteProjectedVisionCache(
    const float * embeddings,
    int32_t n_tokens,
    int32_t projection_dim,
    int32_t grid_x,
    int32_t grid_y,
    int32_t image_max_tokens,
    const char * cache_path,
    char * out_error,
    size_t out_error_cap,
    const char * stage_path
) {
    std::lock_guard<std::mutex> lock(g_staged_mutex);

    BonsaiVisionCacheResult result = {};
    result.code = -1;

    if (out_error != nullptr && out_error_cap > 0) {
        out_error[0] = '\0';
    }

    if (
        embeddings == nullptr ||
        n_tokens <= 0 ||
        projection_dim <= 0 ||
        grid_x <= 0 ||
        grid_y <= 0 ||
        grid_x * grid_y != n_tokens ||
        image_max_tokens <= 0 ||
        cache_path == nullptr ||
        cache_path[0] == '\0'
    ) {
        set_error(
            out_error,
            out_error_cap,
            "invalid MLX projected-vision cache arguments"
        );
        result.code = 1;
        return result;
    }

    write_stage(stage_path, "MLX_INJECT_10_CACHE_WRITE_BEGIN");

    CachedImagePacket packet;
    packet.projection_dim = projection_dim;
    packet.image_max_tokens = image_max_tokens;
    packet.n_tokens = n_tokens;
    packet.n_pos = static_cast<llama_pos>(
        std::max(grid_x, grid_y)
    );
    packet.mrope = true;
    packet.non_causal = false;

    const size_t embedding_count =
        static_cast<size_t>(n_tokens)
        * static_cast<size_t>(projection_dim);
    packet.embeddings.assign(
        embeddings,
        embeddings + embedding_count
    );

    packet.relative_positions.assign(
        static_cast<size_t>(n_tokens) * 4u,
        0
    );
    for (int32_t i = 0; i < n_tokens; ++i) {
        const llama_pos row =
            static_cast<llama_pos>(i / grid_x);
        const llama_pos col =
            static_cast<llama_pos>(i % grid_x);

        // Existing BVCACHE1 stores M-RoPE dimension-major:
        // [t...][y...][x...][z...].
        packet.relative_positions[
            static_cast<size_t>(i)
        ] = 0;
        packet.relative_positions[
            static_cast<size_t>(i + n_tokens)
        ] = row;
        packet.relative_positions[
            static_cast<size_t>(i + n_tokens * 2)
        ] = col;
        packet.relative_positions[
            static_cast<size_t>(i + n_tokens * 3)
        ] = 0;
    }

    if (!save_cached_image(cache_path, packet)) {
        write_stage(stage_path, "MLX_INJECT_11_CACHE_WRITE_FAIL");
        set_error(
            out_error,
            out_error_cap,
            "failed to persist MLX projected vision cache"
        );
        result.code = 2;
        return result;
    }

    result.code = 0;
    result.cache_hit = 0;
    result.image_tokens = n_tokens;
    result.projection_dim = projection_dim;
    result.cache_bytes = file_size_bytes(cache_path);
    result.image_encode_ms = 0.0;

    write_stage(stage_path, "MLX_INJECT_12_CACHE_READY");
    return result;
}

BonsaiVisionCacheResult BonsaiPrepareVisionCache(
    const char * model_path,
    const char * mmproj_path,
    const char * image_path,
    int32_t image_max_tokens,
    const char * cache_path,
    char * out_error,
    size_t out_error_cap,
    const char * stage_path
) {
    std::lock_guard<std::mutex> lock(g_staged_mutex);

    BonsaiVisionCacheResult result = {};
    result.code = -1;

    if (out_error != nullptr && out_error_cap > 0) {
        out_error[0] = '\0';
    }

    if (
        model_path == nullptr ||
        mmproj_path == nullptr ||
        image_path == nullptr ||
        cache_path == nullptr ||
        cache_path[0] == '\0' ||
        image_max_tokens <= 0
    ) {
        set_error(
            out_error,
            out_error_cap,
            "invalid phase-A vision cache arguments"
        );
        result.code = 1;
        return result;
    }

    CachedImagePacket existing;
    if (load_cached_image(
        cache_path,
        image_max_tokens,
        existing
    )) {
        result.code = 0;
        result.cache_hit = 1;
        result.image_tokens = existing.n_tokens;
        result.projection_dim = existing.projection_dim;
        result.cache_bytes = file_size_bytes(cache_path);
        result.image_encode_ms = 0.0;
        write_stage(stage_path, "TWOPHASE_A00_CACHE_HIT");
        return result;
    }

    write_stage(stage_path, "TWOPHASE_A01_VOCAB_BEGIN");

    llama_model_params bootstrap_params =
        llama_model_default_params();
    bootstrap_params.vocab_only = true;
    bootstrap_params.n_gpu_layers = 0;
    bootstrap_params.load_mode = LLAMA_LOAD_MODE_MMAP;

    llama_model * bootstrap = llama_model_load_from_file(
        model_path,
        bootstrap_params
    );
    if (bootstrap == nullptr) {
        write_stage(stage_path, "TWOPHASE_A01_VOCAB_FAIL");
        set_error(
            out_error,
            out_error_cap,
            "vocab-only model load failed"
        );
        result.code = 2;
        return result;
    }

    mtmd_context_params mp = mtmd_context_params_default();
    mp.use_gpu = false;
    mp.print_timings = false;
    mp.n_threads = 4;
    mp.warmup = false;
    mp.image_max_tokens = image_max_tokens;
    mp.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_AUTO;

    write_stage(stage_path, "TWOPHASE_A02_MMPROJ_BEGIN");
    mtmd_context * mctx = mtmd_init_from_file(
        mmproj_path,
        bootstrap,
        mp
    );
    if (mctx == nullptr) {
        write_stage(stage_path, "TWOPHASE_A02_MMPROJ_FAIL");
        llama_model_free(bootstrap);
        set_error(out_error, out_error_cap, "mmproj load failed");
        result.code = 3;
        return result;
    }

    if (!mtmd_support_vision(mctx)) {
        write_stage(stage_path, "TWOPHASE_A02_NOT_VISION");
        mtmd_free(mctx);
        llama_model_free(bootstrap);
        set_error(
            out_error,
            out_error_cap,
            "mmproj has no vision capability"
        );
        result.code = 4;
        return result;
    }

    write_stage(stage_path, "TWOPHASE_A03_IMAGE_LOAD_BEGIN");
    mtmd_helper_bitmap_wrapper wrapper =
        mtmd_helper_bitmap_init_from_file(
            mctx,
            image_path,
            false
        );
    if (wrapper.bitmap == nullptr) {
        write_stage(stage_path, "TWOPHASE_A03_IMAGE_LOAD_FAIL");
        mtmd_free(mctx);
        llama_model_free(bootstrap);
        set_error(out_error, out_error_cap, "image load failed");
        result.code = 5;
        return result;
    }

    const char * marker = mtmd_default_marker();
    std::string prompt =
        "<|im_start|>system\n"
        "You are a helpful assistant.<|im_end|>\n"
        "<|im_start|>user\n";
    prompt += marker;
    prompt +=
        "\nDescribe this image.<|im_end|>\n"
        "<|im_start|>assistant\n";

    mtmd_input_chunks * chunks = mtmd_input_chunks_init();
    if (chunks == nullptr) {
        if (wrapper.video_ctx != nullptr) {
            mtmd_helper_video_free(wrapper.video_ctx);
        }
        mtmd_bitmap_free(wrapper.bitmap);
        mtmd_free(mctx);
        llama_model_free(bootstrap);
        set_error(
            out_error,
            out_error_cap,
            "vision chunk allocation failed"
        );
        result.code = 6;
        return result;
    }

    mtmd_input_text input_text {
        prompt.c_str(),
        prompt.size(),
        true,
        true
    };
    const mtmd_bitmap * bitmaps[1] = { wrapper.bitmap };

    write_stage(stage_path, "TWOPHASE_A04_TOKENIZE_BEGIN");
    const int32_t tokenize_rc = mtmd_tokenize(
        mctx,
        chunks,
        &input_text,
        bitmaps,
        1
    );
    if (tokenize_rc != 0) {
        write_stage(stage_path, "TWOPHASE_A04_TOKENIZE_FAIL");
        mtmd_input_chunks_free(chunks);
        if (wrapper.video_ctx != nullptr) {
            mtmd_helper_video_free(wrapper.video_ctx);
        }
        mtmd_bitmap_free(wrapper.bitmap);
        mtmd_free(mctx);
        llama_model_free(bootstrap);
        set_error(
            out_error,
            out_error_cap,
            "mtmd_tokenize failed: "
                + std::to_string(tokenize_rc)
        );
        result.code = 7;
        return result;
    }

    const int32_t projection_dim =
        read_projection_dim(mmproj_path);
    if (projection_dim <= 0) {
        write_stage(stage_path, "TWOPHASE_A05_PROJECTION_FAIL");
        mtmd_input_chunks_free(chunks);
        if (wrapper.video_ctx != nullptr) {
            mtmd_helper_video_free(wrapper.video_ctx);
        }
        mtmd_bitmap_free(wrapper.bitmap);
        mtmd_free(mctx);
        llama_model_free(bootstrap);
        set_error(
            out_error,
            out_error_cap,
            "projection dimension unavailable"
        );
        result.code = 8;
        return result;
    }

    const bool use_mrope = mtmd_decode_use_mrope(mctx);
    CachedImagePacket cache_candidate;
    int32_t image_chunk_count = 0;
    const auto encode_start = std::chrono::steady_clock::now();

    write_stage(stage_path, "TWOPHASE_A06_ENCODE_BEGIN");

    for (
        size_t ci = 0;
        ci < mtmd_input_chunks_size(chunks);
        ++ci
    ) {
        const mtmd_input_chunk * chunk =
            mtmd_input_chunks_get(chunks, ci);
        if (
            mtmd_input_chunk_get_type(chunk) !=
            MTMD_INPUT_CHUNK_TYPE_IMAGE
        ) {
            continue;
        }

        image_chunk_count += 1;
        if (image_chunk_count > 1) {
            break;
        }

        const int32_t encode_rc = mtmd_encode_chunk(
            mctx,
            chunk
        );
        if (encode_rc != 0) {
            result.code = 9;
            set_error(
                out_error,
                out_error_cap,
                "mtmd_encode_chunk failed: "
                    + std::to_string(encode_rc)
            );
            break;
        }

        const size_t n_tokens =
            mtmd_input_chunk_get_n_tokens(chunk);
        float * embd = mtmd_get_output_embd(mctx);
        if (n_tokens == 0 || embd == nullptr) {
            result.code = 10;
            set_error(
                out_error,
                out_error_cap,
                "image embedding output unavailable"
            );
            break;
        }

        cache_candidate.projection_dim = projection_dim;
        cache_candidate.image_max_tokens = image_max_tokens;
        cache_candidate.n_tokens =
            static_cast<int32_t>(n_tokens);
        cache_candidate.n_pos =
            mtmd_input_chunk_get_n_pos(chunk);
        cache_candidate.mrope = use_mrope;
        cache_candidate.non_causal =
            mtmd_decode_use_non_causal(mctx, chunk);
        cache_candidate.embeddings.assign(
            embd,
            embd
                + n_tokens
                * static_cast<size_t>(projection_dim)
        );

        const mtmd_image_tokens * image_tokens =
            mtmd_input_chunk_get_tokens_image(chunk);
        const size_t dims = use_mrope ? 4 : 1;
        cache_candidate.relative_positions.assign(
            n_tokens * dims,
            0
        );

        for (size_t i = 0; i < n_tokens; ++i) {
            const mtmd_decoder_pos p =
                mtmd_image_tokens_get_decoder_pos(
                    image_tokens,
                    0,
                    i
                );
            if (use_mrope) {
                cache_candidate.relative_positions[i] =
                    static_cast<llama_pos>(p.t);
                cache_candidate.relative_positions[
                    i + n_tokens
                ] = static_cast<llama_pos>(p.y);
                cache_candidate.relative_positions[
                    i + n_tokens * 2
                ] = static_cast<llama_pos>(p.x);
                cache_candidate.relative_positions[
                    i + n_tokens * 3
                ] = static_cast<llama_pos>(p.z);
            } else {
                cache_candidate.relative_positions[i] =
                    static_cast<llama_pos>(p.t);
            }
        }
    }

    result.image_encode_ms = elapsed_ms(
        encode_start,
        std::chrono::steady_clock::now()
    );

    if (
        result.code == -1 &&
        image_chunk_count == 1 &&
        save_cached_image(cache_path, cache_candidate)
    ) {
        result.code = 0;
        result.cache_hit = 0;
        result.image_tokens = cache_candidate.n_tokens;
        result.projection_dim =
            cache_candidate.projection_dim;
        result.cache_bytes = file_size_bytes(cache_path);
        write_stage(stage_path, "TWOPHASE_A99_CACHE_READY");
    } else if (result.code == -1) {
        result.code = 11;
        set_error(
            out_error,
            out_error_cap,
            image_chunk_count == 1
                ? "vision cache save failed"
                : "expected exactly one image chunk"
        );
        write_stage(stage_path, "TWOPHASE_A90_CACHE_FAIL");
    }

    mtmd_input_chunks_free(chunks);
    if (wrapper.video_ctx != nullptr) {
        mtmd_helper_video_free(wrapper.video_ctx);
    }
    mtmd_bitmap_free(wrapper.bitmap);
    mtmd_free(mctx);
    llama_model_free(bootstrap);

    return result;
}

BonsaiVisionPrefillResult BonsaiPrefillCachedVision(
    const struct llama_model * model,
    struct llama_context * ctx,
    const char * cache_path,
    int32_t image_max_tokens,
    const char * system_prompt,
    const char * question,
    int32_t n_batch,
    int32_t non_thinking,
    int32_t reuse_prefix,
    int32_t expected_prefix_positions,
    char * out_error,
    size_t out_error_cap,
    const char * stage_path
) {
    std::lock_guard<std::mutex> lock(g_staged_mutex);

    BonsaiVisionPrefillResult result = {};
    result.code = -1;

    if (out_error != nullptr && out_error_cap > 0) {
        out_error[0] = '\0';
    }

    if (
        model == nullptr ||
        ctx == nullptr ||
        cache_path == nullptr ||
        question == nullptr ||
        n_batch <= 0
    ) {
        set_error(
            out_error,
            out_error_cap,
            "invalid phase-B cached vision arguments"
        );
        result.code = 1;
        return result;
    }

    CachedImagePacket cached;
    if (!load_cached_image(
        cache_path,
        image_max_tokens,
        cached
    )) {
        write_stage(stage_path, "TWOPHASE_B01_CACHE_INVALID");
        set_error(
            out_error,
            out_error_cap,
            "vision embedding cache unavailable"
        );
        result.code = 2;
        return result;
    }

    const int32_t full_n_embd =
        llama_model_n_embd_inp(model);
    if (
        full_n_embd <= 0 ||
        cached.projection_dim != full_n_embd
    ) {
        write_stage(stage_path, "TWOPHASE_B02_WIDTH_MISMATCH");
        set_error(
            out_error,
            out_error_cap,
            "cached vision embedding width mismatch"
        );
        result.code = 3;
        return result;
    }

    const llama_vocab * vocab =
        llama_model_get_vocab(model);
    if (vocab == nullptr) {
        result.code = 4;
        set_error(
            out_error,
            out_error_cap,
            "model vocab unavailable"
        );
        return result;
    }

    const std::string system =
        system_prompt != nullptr
            ? std::string(system_prompt)
            : std::string();

    const std::string prefix =
        (system.empty()
            ? std::string()
            : std::string("<|im_start|>system\n")
                + system
                + "<|im_end|>\n")
        + "<|im_start|>user\n"
        + "<|vision_start|>";

    std::string suffix =
        std::string("<|vision_end|>\n")
        + question
        + "<|im_end|>\n"
        + "<|im_start|>assistant\n";

    if (non_thinking != 0) {
        suffix += "<think>\n\n</think>\n\n";
    }

    std::vector<PacketChunk> packet;
    packet.reserve(3);

    PacketChunk prefix_chunk;
    prefix_chunk.kind = PacketKind::Text;
    if (!tokenize_text_exact(
        vocab,
        prefix,
        true,
        prefix_chunk.tokens
    )) {
        result.code = 5;
        set_error(
            out_error,
            out_error_cap,
            "vision prefix tokenization failed"
        );
        return result;
    }

    if (llama_vocab_get_add_bos(vocab)) {
        prefix_chunk.tokens.insert(
            prefix_chunk.tokens.begin(),
            llama_vocab_bos(vocab)
        );
    }
    prefix_chunk.n_pos =
        static_cast<llama_pos>(
            prefix_chunk.tokens.size()
        );

    PacketChunk image_chunk;
    image_chunk.kind = PacketKind::Image;
    image_chunk.embeddings = cached.embeddings;
    image_chunk.n_pos = cached.n_pos;
    image_chunk.mrope = cached.mrope;
    image_chunk.non_causal = cached.non_causal;
    image_chunk.positions = cached.relative_positions;

    const llama_pos image_pos_0 = prefix_chunk.n_pos;
    if (image_chunk.mrope) {
        const size_t n =
            static_cast<size_t>(cached.n_tokens);
        for (size_t i = 0; i < n; ++i) {
            image_chunk.positions[i] += image_pos_0;
            image_chunk.positions[i + n] += image_pos_0;
            image_chunk.positions[i + n * 2] += image_pos_0;
        }
    } else {
        for (auto & p : image_chunk.positions) {
            p += image_pos_0;
        }
    }

    PacketChunk suffix_chunk;
    suffix_chunk.kind = PacketKind::Text;
    if (!tokenize_text_exact(
        vocab,
        suffix,
        true,
        suffix_chunk.tokens
    )) {
        result.code = 6;
        set_error(
            out_error,
            out_error_cap,
            "vision suffix tokenization failed"
        );
        return result;
    }
    if (llama_vocab_get_add_eos(vocab)) {
        suffix_chunk.tokens.push_back(
            llama_vocab_eos(vocab)
        );
    }
    suffix_chunk.n_pos =
        static_cast<llama_pos>(
            suffix_chunk.tokens.size()
        );

    packet.push_back(std::move(prefix_chunk));
    packet.push_back(std::move(image_chunk));
    packet.push_back(std::move(suffix_chunk));

    const llama_pos prefix_positions =
        packet[0].n_pos + packet[1].n_pos;
    const bool can_reuse_prefix =
        reuse_prefix != 0 &&
        expected_prefix_positions > 0 &&
        expected_prefix_positions == prefix_positions;

    llama_pos n_past = 0;
    if (can_reuse_prefix) {
        n_past = prefix_positions;
        result.prefix_reuse_hit = 1;
        write_stage(
            stage_path,
            "TWOPHASE_B03_PREFIX_REUSE_HIT"
        );
    } else {
        llama_memory_clear(
            llama_get_memory(ctx),
            true
        );
        result.prefix_reuse_hit = 0;
        write_stage(
            stage_path,
            "TWOPHASE_B03_PREFIX_REUSE_MISS"
        );
    }

    const auto prefill_start =
        std::chrono::steady_clock::now();
    write_stage(stage_path, "TWOPHASE_B03_PREFILL_BEGIN");

    const size_t begin_index =
        can_reuse_prefix ? 2u : 0u;

    for (size_t i = begin_index; i < packet.size(); ++i) {
        const bool is_last = i + 1 == packet.size();
        const auto chunk_start =
            std::chrono::steady_clock::now();

        const int32_t rc =
            packet[i].kind == PacketKind::Text
                ? decode_text_chunk(
                    ctx,
                    packet[i],
                    n_past,
                    n_batch,
                    is_last
                )
                : decode_image_chunk(
                    ctx,
                    packet[i],
                    full_n_embd,
                    n_past,
                    n_batch,
                    is_last
                );

        const double chunk_ms = elapsed_ms(
            chunk_start,
            std::chrono::steady_clock::now()
        );

        if (i == 0) {
            result.prefix_text_ms = chunk_ms;
        } else if (i == 1) {
            result.image_prefill_ms = chunk_ms;
        } else if (i == 2) {
            result.suffix_prefill_ms = chunk_ms;
        }

        if (rc != 0) {
            llama_memory_clear(
                llama_get_memory(ctx),
                true
            );
            write_stage(
                stage_path,
                "TWOPHASE_B03_PREFILL_FAIL_CLEANED"
            );
            set_error(
                out_error,
                out_error_cap,
                "cached vision prefill failed: "
                    + std::to_string(rc)
            );
            result.code = 7;
            return result;
        }
    }

    result.prefill_ms = elapsed_ms(
        prefill_start,
        std::chrono::steady_clock::now()
    );
    result.prefix_positions =
        static_cast<int32_t>(prefix_positions);
    result.prompt_tokens =
        static_cast<int32_t>(
            packet[0].tokens.size()
        )
        + cached.n_tokens
        + static_cast<int32_t>(
            packet[2].tokens.size()
        );
    result.image_tokens = cached.n_tokens;
    result.projection_dim =
        cached.projection_dim;
    result.input_positions =
        static_cast<int32_t>(n_past);
    result.code = 0;

    write_stage(stage_path, "TWOPHASE_B99_PREFILL_READY");
    return result;
}

int32_t BonsaiRetainVisionPrefixKV(
    struct llama_context * ctx,
    int32_t prefix_positions
) {
    std::lock_guard<std::mutex> lock(g_staged_mutex);

    if (ctx == nullptr || prefix_positions <= 0) {
        return 0;
    }

    llama_memory_t mem = llama_get_memory(ctx);
    if (mem == nullptr) {
        return 0;
    }

    const bool ok = llama_memory_seq_rm(
        mem,
        0,
        static_cast<llama_pos>(prefix_positions),
        -1
    );

    if (!ok) {
        llama_memory_clear(mem, true);
        return 0;
    }

    return 1;
}

void BonsaiReleaseStagedResidentModel(void) {
    std::lock_guard<std::mutex> lock(g_staged_mutex);
    release_resident_model_locked();
}

BonsaiStagedVisionResult BonsaiRunStagedVision(
    const char * model_path,
    const char * mmproj_path,
    const char * image_path,
    const char * question,
    int32_t image_max_tokens,
    int32_t n_ctx,
    int32_t n_batch,
    int32_t n_ubatch,
    int32_t gpu_layers,
    int32_t max_new_tokens,
    int32_t accelerated_mode,
    const char * cache_path,
    char * out_text,
    size_t out_text_cap,
    char * out_error,
    size_t out_error_cap,
    const char * stage_path,
    BonsaiStagedStreamCallback stream_callback,
    void * stream_user_data
) {
    std::lock_guard<std::mutex> staged_lock(g_staged_mutex);

    BonsaiStagedVisionResult result = {};
    result.code = -1;

    if (out_text != nullptr && out_text_cap > 0) {
        out_text[0] = '\0';
    }
    if (out_error != nullptr && out_error_cap > 0) {
        out_error[0] = '\0';
    }

    if (
        model_path == nullptr ||
        mmproj_path == nullptr ||
        image_path == nullptr ||
        question == nullptr ||
        n_ctx < 256 ||
        n_batch <= 0 ||
        n_ubatch <= 0 ||
        n_ubatch > n_batch ||
        max_new_tokens <= 0 ||
        (accelerated_mode != 0 && accelerated_mode != 1)
    ) {
        set_error(out_error, out_error_cap, "invalid staged vision arguments");
        result.code = 1;
        return result;
    }

    write_stage(stage_path, "STAGED_01_VOCAB_MODEL_BEGIN");

    llama_model_params bootstrap_params = llama_model_default_params();
    bootstrap_params.vocab_only = true;
    bootstrap_params.n_gpu_layers = 0;
    bootstrap_params.load_mode = LLAMA_LOAD_MODE_MMAP;

    llama_model * bootstrap = llama_model_load_from_file(
        model_path,
        bootstrap_params
    );

    if (bootstrap == nullptr) {
        write_stage(stage_path, "STAGED_01_VOCAB_MODEL_FAIL");
        set_error(out_error, out_error_cap, "vocab-only model load failed");
        result.code = 2;
        return result;
    }

    write_stage(stage_path, "STAGED_01_VOCAB_MODEL_DONE");

    std::vector<PacketChunk> packet;
    llama_pos stage_a_pos = 0;

    CachedImagePacket cached_image;
    bool cache_hit = load_cached_image(
        cache_path,
        image_max_tokens,
        cached_image
    );

    if (cache_hit) {
        int32_t cached_prompt_tokens = 0;
        if (!build_packet_from_cached_image(
            bootstrap,
            question,
            cached_image,
            packet,
            stage_a_pos,
            cached_prompt_tokens
        )) {
            cache_hit = false;
            if (cache_path != nullptr && cache_path[0] != '\0') {
                std::remove(cache_path);
            }
            packet.clear();
            stage_a_pos = 0;
            write_stage(stage_path, "STAGED_03_IMAGE_CACHE_INVALID");
        } else {
            result.cache_hit = 1;
            result.cache_bytes = file_size_bytes(cache_path);
            result.projection_dim = cached_image.projection_dim;
            result.image_tokens = cached_image.n_tokens;
            result.prompt_tokens = cached_prompt_tokens;
            result.image_encode_ms = 0.0;
            write_stage(stage_path, "STAGED_03_IMAGE_CACHE_HIT");

            llama_model_free(bootstrap);
            bootstrap = nullptr;
        }
    }

    if (
        !cache_hit ||
        !resident_model_matches(model_path, gpu_layers)
    ) {
        release_resident_model_locked();
    }

    if (!cache_hit) {
    mtmd_context_params mp = mtmd_context_params_default();
    mp.use_gpu = false;
    mp.print_timings = false;
    mp.n_threads = 4;
    mp.warmup = false;
    mp.image_max_tokens = image_max_tokens;
    mp.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_AUTO;

    write_stage(stage_path, "STAGED_02_MMPROJ_BEGIN");
    mtmd_context * mctx = mtmd_init_from_file(
        mmproj_path,
        bootstrap,
        mp
    );

    if (mctx == nullptr) {
        write_stage(stage_path, "STAGED_02_MMPROJ_FAIL");
        llama_model_free(bootstrap);
        set_error(out_error, out_error_cap, "mmproj load failed");
        result.code = 3;
        return result;
    }

    if (!mtmd_support_vision(mctx)) {
        write_stage(stage_path, "STAGED_02_MMPROJ_NOT_VISION");
        mtmd_free(mctx);
        llama_model_free(bootstrap);
        set_error(out_error, out_error_cap, "mmproj has no vision capability");
        result.code = 4;
        return result;
    }

    write_stage(stage_path, "STAGED_02_MMPROJ_DONE");

    mtmd_helper_bitmap_wrapper wrapper =
        mtmd_helper_bitmap_init_from_file(
            mctx,
            image_path,
            false
        );

    if (wrapper.bitmap == nullptr) {
        write_stage(stage_path, "STAGED_03_IMAGE_LOAD_FAIL");
        mtmd_free(mctx);
        llama_model_free(bootstrap);
        set_error(out_error, out_error_cap, "image load failed");
        result.code = 5;
        return result;
    }

    const char * marker = mtmd_default_marker();
    std::string prompt =
        "<|im_start|>system\n"
        "You are a helpful assistant.<|im_end|>\n"
        "<|im_start|>user\n";
    prompt += marker;
    prompt += "\n";
    prompt += question;
    prompt +=
        "<|im_end|>\n"
        "<|im_start|>assistant\n";

    mtmd_input_chunks * chunks = mtmd_input_chunks_init();
    if (chunks == nullptr) {
        if (wrapper.video_ctx != nullptr) {
            mtmd_helper_video_free(wrapper.video_ctx);
        }
        mtmd_bitmap_free(wrapper.bitmap);
        mtmd_free(mctx);
        llama_model_free(bootstrap);
        set_error(out_error, out_error_cap, "chunk allocation failed");
        result.code = 6;
        return result;
    }

    mtmd_input_text input_text {
        prompt.c_str(),
        prompt.size(),
        true,
        true
    };
    const mtmd_bitmap * bitmaps[1] = { wrapper.bitmap };

    write_stage(stage_path, "STAGED_03_TOKENIZE_BEGIN");
    const int32_t tok_rc = mtmd_tokenize(
        mctx,
        chunks,
        &input_text,
        bitmaps,
        1
    );

    if (tok_rc != 0) {
        write_stage(stage_path, "STAGED_03_TOKENIZE_FAIL");
        mtmd_input_chunks_free(chunks);
        if (wrapper.video_ctx != nullptr) {
            mtmd_helper_video_free(wrapper.video_ctx);
        }
        mtmd_bitmap_free(wrapper.bitmap);
        mtmd_free(mctx);
        llama_model_free(bootstrap);
        set_error(
            out_error,
            out_error_cap,
            "mtmd_tokenize failed: " + std::to_string(tok_rc)
        );
        result.code = 7;
        return result;
    }

    // IMPORTANT: a vocab-only text model does not provide reliable
    // hparams for the embedding width. Strata's production vision helper
    // reads the projector output width directly from the mmproj GGUF.
    const int32_t n_embd = read_projection_dim(mmproj_path);
    result.projection_dim = n_embd;
    if (n_embd <= 0) {
        write_stage(stage_path, "STAGED_04_PROJECTION_DIM_FAIL");
        mtmd_input_chunks_free(chunks);
        if (wrapper.video_ctx != nullptr) {
            mtmd_helper_video_free(wrapper.video_ctx);
        }
        mtmd_bitmap_free(wrapper.bitmap);
        mtmd_free(mctx);
        llama_model_free(bootstrap);
        set_error(
            out_error,
            out_error_cap,
            "mmproj clip.vision.projection_dim unavailable"
        );
        result.code = 10;
        return result;
    }

    const bool use_mrope = mtmd_decode_use_mrope(mctx);

    packet.clear();
    packet.reserve(mtmd_input_chunks_size(chunks));

    CachedImagePacket cache_candidate;
    int32_t image_chunk_count = 0;

    const auto encode_start = std::chrono::steady_clock::now();

    write_stage(stage_path, "STAGED_04_IMAGE_ENCODE_BEGIN");

    for (
        size_t ci = 0;
        ci < mtmd_input_chunks_size(chunks);
        ++ci
    ) {
        const mtmd_input_chunk * chunk =
            mtmd_input_chunks_get(chunks, ci);
        const mtmd_input_chunk_type type =
            mtmd_input_chunk_get_type(chunk);

        PacketChunk out;

        if (type == MTMD_INPUT_CHUNK_TYPE_TEXT) {
            out.kind = PacketKind::Text;

            size_t n_tokens = 0;
            const llama_token * tokens =
                mtmd_input_chunk_get_tokens_text(
                    chunk,
                    &n_tokens
                );

            if (tokens == nullptr && n_tokens > 0) {
                write_stage(stage_path, "STAGED_04_TEXT_COPY_FAIL");
                mtmd_input_chunks_free(chunks);
                if (wrapper.video_ctx != nullptr) {
                    mtmd_helper_video_free(wrapper.video_ctx);
                }
                mtmd_bitmap_free(wrapper.bitmap);
                mtmd_free(mctx);
                llama_model_free(bootstrap);
                set_error(out_error, out_error_cap, "text token copy failed");
                result.code = 8;
                return result;
            }

            out.tokens.assign(tokens, tokens + n_tokens);
            out.n_pos = static_cast<llama_pos>(n_tokens);
            stage_a_pos += out.n_pos;
            result.prompt_tokens += static_cast<int32_t>(n_tokens);
        } else if (type == MTMD_INPUT_CHUNK_TYPE_IMAGE) {
            out.kind = PacketKind::Image;
            out.mrope = use_mrope;
            out.non_causal = mtmd_decode_use_non_causal(
                mctx,
                chunk
            );
            out.n_pos = mtmd_input_chunk_get_n_pos(chunk);

            const int32_t enc_rc = mtmd_encode_chunk(
                mctx,
                chunk
            );
            if (enc_rc != 0) {
                write_stage(stage_path, "STAGED_04_IMAGE_ENCODE_FAIL");
                mtmd_input_chunks_free(chunks);
                if (wrapper.video_ctx != nullptr) {
                    mtmd_helper_video_free(wrapper.video_ctx);
                }
                mtmd_bitmap_free(wrapper.bitmap);
                mtmd_free(mctx);
                llama_model_free(bootstrap);
                set_error(
                    out_error,
                    out_error_cap,
                    "mtmd_encode_chunk failed: " + std::to_string(enc_rc)
                );
                result.code = 9;
                return result;
            }

            const size_t n_tokens =
                mtmd_input_chunk_get_n_tokens(chunk);
            float * embd = mtmd_get_output_embd(mctx);

            if (n_tokens == 0) {
                write_stage(stage_path, "STAGED_04_IMAGE_TOKEN_COUNT_ZERO");
                mtmd_input_chunks_free(chunks);
                if (wrapper.video_ctx != nullptr) {
                    mtmd_helper_video_free(wrapper.video_ctx);
                }
                mtmd_bitmap_free(wrapper.bitmap);
                mtmd_free(mctx);
                llama_model_free(bootstrap);
                set_error(out_error, out_error_cap, "image token count is zero");
                result.code = 11;
                return result;
            }

            if (embd == nullptr) {
                write_stage(stage_path, "STAGED_04_IMAGE_EMBD_PTR_NULL");
                mtmd_input_chunks_free(chunks);
                if (wrapper.video_ctx != nullptr) {
                    mtmd_helper_video_free(wrapper.video_ctx);
                }
                mtmd_bitmap_free(wrapper.bitmap);
                mtmd_free(mctx);
                llama_model_free(bootstrap);
                set_error(out_error, out_error_cap, "mtmd output embedding pointer is null");
                result.code = 12;
                return result;
            }

            out.embeddings.assign(
                embd,
                embd
                    + n_tokens
                    * static_cast<size_t>(n_embd)
            );

            if (use_mrope) {
                out.positions.resize(n_tokens * 4);
                const mtmd_image_tokens * image_tokens =
                    mtmd_input_chunk_get_tokens_image(chunk);

                for (size_t i = 0; i < n_tokens; ++i) {
                    const mtmd_decoder_pos p =
                        mtmd_image_tokens_get_decoder_pos(
                            image_tokens,
                            stage_a_pos,
                            i
                        );

                    out.positions[i] = static_cast<llama_pos>(p.t);
                    out.positions[i + n_tokens] =
                        static_cast<llama_pos>(p.y);
                    out.positions[i + n_tokens * 2] =
                        static_cast<llama_pos>(p.x);
                    out.positions[i + n_tokens * 3] =
                        static_cast<llama_pos>(p.z);
                }
            } else {
                out.positions.resize(n_tokens);
                for (size_t i = 0; i < n_tokens; ++i) {
                    out.positions[i] =
                        stage_a_pos + static_cast<llama_pos>(i);
                }
            }

            image_chunk_count += 1;
            if (image_chunk_count == 1) {
                cache_candidate.projection_dim = n_embd;
                cache_candidate.image_max_tokens = image_max_tokens;
                cache_candidate.n_tokens =
                    static_cast<int32_t>(n_tokens);
                cache_candidate.n_pos = out.n_pos;
                cache_candidate.mrope = out.mrope;
                cache_candidate.non_causal = out.non_causal;
                cache_candidate.embeddings = out.embeddings;

                const mtmd_image_tokens * image_tokens =
                    mtmd_input_chunk_get_tokens_image(chunk);
                const size_t dims = use_mrope ? 4 : 1;
                cache_candidate.relative_positions.assign(
                    n_tokens * dims,
                    0
                );

                for (size_t i = 0; i < n_tokens; ++i) {
                    const mtmd_decoder_pos p =
                        mtmd_image_tokens_get_decoder_pos(
                            image_tokens,
                            0,
                            i
                        );

                    if (use_mrope) {
                        cache_candidate.relative_positions[i] =
                            static_cast<llama_pos>(p.t);
                        cache_candidate.relative_positions[
                            i + n_tokens
                        ] = static_cast<llama_pos>(p.y);
                        cache_candidate.relative_positions[
                            i + n_tokens * 2
                        ] = static_cast<llama_pos>(p.x);
                        cache_candidate.relative_positions[
                            i + n_tokens * 3
                        ] = static_cast<llama_pos>(p.z);
                    } else {
                        cache_candidate.relative_positions[i] =
                            static_cast<llama_pos>(p.t);
                    }
                }
            } else {
                // v1 cache intentionally supports one image chunk only.
                cache_candidate = {};
            }

            stage_a_pos += out.n_pos;
            result.image_tokens += static_cast<int32_t>(n_tokens);
            result.prompt_tokens += static_cast<int32_t>(n_tokens);
        } else {
            write_stage(stage_path, "STAGED_04_UNSUPPORTED_CHUNK");
            mtmd_input_chunks_free(chunks);
            if (wrapper.video_ctx != nullptr) {
                mtmd_helper_video_free(wrapper.video_ctx);
            }
            mtmd_bitmap_free(wrapper.bitmap);
            mtmd_free(mctx);
            llama_model_free(bootstrap);
            set_error(out_error, out_error_cap, "unsupported media chunk");
            result.code = 13;
            return result;
        }

        packet.push_back(std::move(out));
    }

    result.image_encode_ms = elapsed_ms(
        encode_start,
        std::chrono::steady_clock::now()
    );

    write_stage(stage_path, "STAGED_04_IMAGE_ENCODE_DONE");

    result.cache_hit = 0;
    if (
        image_chunk_count == 1 &&
        cache_path != nullptr &&
        cache_path[0] != '\0'
    ) {
        // Before persisting a cache entry, reconstruct the packet using the
        // cache-hit path and require byte-identical tokens/embeddings/positions.
        // This guards the Bonsai/Qwen boundary-token reconstruction against
        // silently drifting from Prism mtmd.
        std::vector<PacketChunk> reconstructed;
        llama_pos reconstructed_pos = 0;
        int32_t reconstructed_prompt_tokens = 0;

        const bool reconstructed_ok =
            build_packet_from_cached_image(
                bootstrap,
                question,
                cache_candidate,
                reconstructed,
                reconstructed_pos,
                reconstructed_prompt_tokens
            );

        const bool equivalent =
            reconstructed_ok &&
            reconstructed_pos == stage_a_pos &&
            reconstructed_prompt_tokens == result.prompt_tokens &&
            packets_equal(packet, reconstructed);

        if (
            equivalent &&
            save_cached_image(cache_path, cache_candidate)
        ) {
            result.cache_bytes = file_size_bytes(cache_path);
            write_stage(
                stage_path,
                "STAGED_04_IMAGE_CACHE_SELF_CHECK_PASS"
            );
        } else {
            std::remove(cache_path);
            write_stage(
                stage_path,
                "STAGED_04_IMAGE_CACHE_SELF_CHECK_SKIP"
            );
        }
    }

    // Critical mobile-memory boundary:
    // the projector and vocab-only model are fully released before
    // the full 27B model and llama context are created.
    mtmd_input_chunks_free(chunks);
    if (wrapper.video_ctx != nullptr) {
        mtmd_helper_video_free(wrapper.video_ctx);
    }
    mtmd_bitmap_free(wrapper.bitmap);
    mtmd_free(mctx);
    llama_model_free(bootstrap);
    mctx = nullptr;
    bootstrap = nullptr;
    } // !cache_hit

    write_stage(
        stage_path,
        cache_hit
            ? "STAGED_05_CACHE_READY"
            : "STAGED_05_PROJECTOR_RELEASED"
    );

    // Use the user's requested Max Tokens, but cap it only by the
    // context positions that remain after the multimodal prompt.
    // RC1.10/RC1.10.1 had a temporary fixed 64-token cap in Swift;
    // RC1.10.2 removes that test cap and computes the real budget here.
    result.input_positions = static_cast<int32_t>(stage_a_pos);
    result.requested_max_tokens = max_new_tokens;

    const int32_t available_output_tokens =
        n_ctx - static_cast<int32_t>(stage_a_pos) - 1;

    if (available_output_tokens <= 0) {
        set_error(
            out_error,
            out_error_cap,
            "encoded prompt uses " + std::to_string(stage_a_pos)
                + " positions; context "
                + std::to_string(n_ctx)
                + " leaves no room for output"
        );
        result.code = 14;
        return result;
    }

    const int32_t effective_max_tokens =
        std::min(max_new_tokens, available_output_tokens);
    result.effective_max_tokens = effective_max_tokens;

    write_stage(stage_path, "STAGED_05_OUTPUT_BUDGET_READY");
    write_stage(stage_path, "STAGED_06_FULL_MODEL_BEGIN");

    llama_model * model = nullptr;
    bool reused_resident_model = false;

    if (
        cache_hit &&
        resident_model_matches(model_path, gpu_layers)
    ) {
        model = g_resident_model;
        reused_resident_model = true;
        result.resident_model_hit = 1;
        result.full_model_load_ms = 0.0;
        write_stage(stage_path, "STAGED_06_RESIDENT_MODEL_HIT");
    } else {
        llama_model_params model_params = llama_model_default_params();
        model_params.n_gpu_layers = gpu_layers;
        model_params.load_mode = LLAMA_LOAD_MODE_MMAP;

        const auto model_start = std::chrono::steady_clock::now();
        model = llama_model_load_from_file(
            model_path,
            model_params
        );
        result.full_model_load_ms = elapsed_ms(
            model_start,
            std::chrono::steady_clock::now()
        );

        if (model == nullptr) {
            write_stage(stage_path, "STAGED_06_FULL_MODEL_FAIL");
            set_error(
                out_error,
                out_error_cap,
                "full model load failed"
            );
            result.code = 15;
            return result;
        }

        result.resident_model_hit = 0;
        write_stage(stage_path, "STAGED_06_FULL_MODEL_DONE");
    }

    const int32_t full_n_embd = llama_model_n_embd_inp(model);
    if (
        full_n_embd <= 0 ||
        result.projection_dim <= 0 ||
        full_n_embd != result.projection_dim
    ) {
        write_stage(stage_path, "STAGED_06_EMBEDDING_WIDTH_MISMATCH");
        set_error(
            out_error,
            out_error_cap,
            "vision embedding width does not match the full model"
        );
        result.code = 20;
        if (reused_resident_model) {
            release_resident_model_locked();
        } else {
            llama_model_free(model);
        }
        return result;
    }

    auto release_model_after_failure = [&]() {
        if (reused_resident_model) {
            release_resident_model_locked();
        } else if (model != nullptr) {
            llama_model_free(model);
        }
        model = nullptr;
    };

    const bool reuse_context =
        cache_hit && reused_resident_model &&
        resident_context_matches(
            cache_path, n_ctx, n_batch, n_ubatch, accelerated_mode
        );

    llama_context_params cp = llama_context_default_params();
    cp.n_ctx = static_cast<uint32_t>(n_ctx);
    cp.n_batch = static_cast<uint32_t>(n_batch);
    cp.n_ubatch = static_cast<uint32_t>(n_ubatch);
    cp.n_seq_max = 1;
    cp.n_outputs_max = 1;
    cp.n_outputs_max_per_seq = 1;
    cp.swa_full = false;
    cp.kv_unified = true;

    // RC1.11 performance candidate:
    // staged execution has already released mmproj before the LLM context
    // exists, so the aggressive low-memory context flags used during the
    // coexistence-debug era are no longer mandatory.
    result.accelerated_mode = accelerated_mode;
    if (accelerated_mode == 1) {
        cp.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED;
        cp.offload_kqv = true;
        cp.op_offload = true;
        write_stage(stage_path, "STAGED_07_CONTEXT_ACCELERATED");
    } else {
        cp.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_DISABLED;
        cp.offload_kqv = false;
        cp.op_offload = false;
        write_stage(stage_path, "STAGED_07_CONTEXT_SAFE");
    }

    cp.n_threads = 4;
    cp.n_threads_batch = 4;

    llama_context * ctx = nullptr;
    llama_pos n_past = 0;

    if (reuse_context) {
        ctx = g_resident_ctx;
        n_past = g_resident_n_past;
        result.resident_context_hit = 1;
        result.kv_reuse_hit = 1;
        result.context_create_ms = 0.0;
        write_stage(stage_path, "STAGED_07_CONTEXT_RESIDENT_HIT");

        const std::string followup =
            "<|im_end|>\n<|im_start|>user\n" +
            std::string(question) +
            "<|im_end|>\n<|im_start|>assistant\n";
        PacketChunk followup_chunk;
        followup_chunk.kind = PacketKind::Text;
        if (!tokenize_text_exact(
            llama_model_get_vocab(model), followup, true,
            followup_chunk.tokens
        )) {
            release_resident_context_locked();
            set_error(out_error, out_error_cap, "follow-up tokenization failed");
            result.code = 21;
            return result;
        }
        followup_chunk.n_pos = static_cast<llama_pos>(
            followup_chunk.tokens.size()
        );
        if (n_past + followup_chunk.n_pos + max_new_tokens + 1 > n_ctx) {
            release_resident_context_locked();
            set_error(
                out_error, out_error_cap,
                "persistent session context exhausted; start a new session"
            );
            result.code = 22;
            return result;
        }
        write_stage(stage_path, "STAGED_08_KV_FOLLOWUP_DECODE_BEGIN");
        const int32_t rc = decode_text_chunk(
            ctx, followup_chunk, n_past, n_batch, true
        );
        if (rc != 0) {
            release_resident_context_locked();
            release_model_after_failure();
            set_error(
                out_error, out_error_cap,
                "follow-up llama_decode failed: " + std::to_string(rc)
            );
            result.code = 23;
            return result;
        }
        write_stage(stage_path, "STAGED_08_KV_FOLLOWUP_DECODE_DONE");
        result.input_positions = static_cast<int32_t>(n_past);
        result.effective_max_tokens = std::min(
            max_new_tokens, n_ctx - static_cast<int32_t>(n_past) - 1
        );
    } else {
        release_resident_context_locked();
        write_stage(stage_path, "STAGED_07_CONTEXT_BEGIN");
        const auto ctx_start = std::chrono::steady_clock::now();
        ctx = llama_init_from_model(model, cp);
        result.context_create_ms = elapsed_ms(
            ctx_start, std::chrono::steady_clock::now()
        );
        if (ctx == nullptr) {
            write_stage(stage_path, "STAGED_07_CONTEXT_FAIL");
            release_model_after_failure();
            set_error(out_error, out_error_cap, "llama context creation failed");
            result.code = 16;
            return result;
        }
        write_stage(stage_path, "STAGED_07_CONTEXT_DONE");
        write_stage(stage_path, "STAGED_08_PACKET_DECODE_BEGIN");
        for (size_t i = 0; i < packet.size(); ++i) {
            const bool is_last = i + 1 == packet.size();
            int32_t rc = packet[i].kind == PacketKind::Text
                ? decode_text_chunk(ctx, packet[i], n_past, n_batch, is_last)
                : decode_image_chunk(
                    ctx, packet[i], full_n_embd, n_past, n_batch, is_last
                );
            if (rc != 0) {
                write_stage(stage_path, "STAGED_08_PACKET_DECODE_FAIL");
                llama_free(ctx);
                release_model_after_failure();
                set_error(
                    out_error, out_error_cap,
                    "packet llama_decode failed: " + std::to_string(rc)
                );
                result.code = 17;
                return result;
            }
        }
        write_stage(stage_path, "STAGED_08_PACKET_DECODE_DONE");
        result.resident_context_hit = 0;
        result.kv_reuse_hit = 0;
    }

    llama_sampler * sampler = llama_sampler_init_greedy();
    if (sampler == nullptr) {
        if (ctx == g_resident_ctx) release_resident_context_locked();
        else llama_free(ctx);
        release_model_after_failure();
        set_error(out_error, out_error_cap, "sampler creation failed");
        result.code = 18;
        return result;
    }

    const llama_vocab * vocab = llama_model_get_vocab(model);
    std::string output;
    output.reserve(static_cast<size_t>(result.effective_max_tokens) * 8);

    const auto gen_start = std::chrono::steady_clock::now();
    write_stage(stage_path, "STAGED_09_GENERATION_BEGIN");

    for (int32_t i = 0; i < result.effective_max_tokens; ++i) {
        const llama_token token = llama_sampler_sample(
            sampler,
            ctx,
            -1
        );

        if (llama_vocab_is_eog(vocab, token)) {
            break;
        }

        const std::string piece = token_piece(vocab, token);
        output += piece;
        if (stream_callback != nullptr && stream_user_data != nullptr && !piece.empty()) {
            stream_callback(piece.data(), piece.size(), stream_user_data);
        }
        result.generated_tokens += 1;

        llama_batch batch = llama_batch_init(1, 0, 1);
        batch.n_tokens = 1;
        batch.token[0] = token;
        batch.pos[0] = n_past;
        batch.n_seq_id[0] = 1;
        batch.seq_id[0][0] = 0;
        batch.logits[0] = 1;

        const int32_t rc = llama_decode(ctx, batch);
        llama_batch_free(batch);

        if (rc != 0) {
            write_stage(stage_path, "STAGED_09_GENERATION_DECODE_FAIL");
            llama_sampler_free(sampler);
            if (ctx == g_resident_ctx) release_resident_context_locked();
            else llama_free(ctx);
            release_model_after_failure();
            set_error(
                out_error,
                out_error_cap,
                "generation llama_decode failed: "
                    + std::to_string(rc)
            );
            result.code = 19;
            return result;
        }

        n_past += 1;
    }

    result.generation_ms = elapsed_ms(
        gen_start,
        std::chrono::steady_clock::now()
    );
    result.final_position = n_past;

    llama_sampler_free(sampler);

    if (!reused_resident_model) {
        release_resident_model_locked();
        g_resident_model = model;
        g_resident_model_path = model_path;
        g_resident_gpu_layers = gpu_layers;
        model = nullptr;
        write_stage(stage_path, "STAGED_10_MODEL_KEPT_RESIDENT");
    } else {
        write_stage(stage_path, "STAGED_10_RESIDENT_MODEL_REUSED");
    }

    if (g_resident_ctx != nullptr && g_resident_ctx != ctx) {
        release_resident_context_locked();
    }
    g_resident_ctx = ctx;
    g_resident_session_key = cache_path != nullptr ? cache_path : "";
    g_resident_n_past = n_past;
    g_resident_n_ctx = n_ctx;
    g_resident_n_batch = n_batch;
    g_resident_n_ubatch = n_ubatch;
    g_resident_accelerated_mode = accelerated_mode;
    write_stage(
        stage_path,
        reuse_context
            ? "STAGED_10_CONTEXT_KEPT_RESIDENT_KV_REUSED"
            : "STAGED_10_CONTEXT_KEPT_RESIDENT"
    );

    if (out_text != nullptr && out_text_cap > 0) {
        std::snprintf(out_text, out_text_cap, "%s", output.c_str());
    }

    result.code = 0;
    write_stage(stage_path, "STAGED_99_PASS");
    return result;
}
