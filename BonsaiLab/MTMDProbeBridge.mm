#include "MTMDProbeBridge.h"

#include <llama/llama.h>
#include <llama/mtmd.h>

#include <cstdio>
#include <unistd.h>

static void persist_progress(const char * path, int value) {
    if (path == nullptr || path[0] == '\0') {
        return;
    }

    FILE * f = std::fopen(path, "w");
    if (f == nullptr) {
        return;
    }

    std::fprintf(f, "%d\n", value);
    std::fflush(f);
    fsync(fileno(f));
    std::fclose(f);
}

static bool bonsai_progress_callback(float progress, void * user_data) {
    const char * path = static_cast<const char *>(user_data);
    const int pct = static_cast<int>(progress * 100.0f + 0.5f);
    persist_progress(path, pct);
    return true;
}

BonsaiMTMDOnlyProbeResult BonsaiProbeMTMD(
    const char * path,
    const struct llama_model * text_model,
    bool use_gpu,
    int32_t image_max_tokens,
    const char * progress_path
) {
    BonsaiMTMDOnlyProbeResult out = {0, 0};

    if (path == nullptr || path[0] == '\0') {
        persist_progress(progress_path, -10);
        return out;
    }

    mtmd_context_params params = mtmd_context_params_default();
    params.use_gpu = use_gpu;
    params.print_timings = false;
    params.warmup = false;
    params.image_max_tokens = image_max_tokens;
    params.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_AUTO;
    params.progress_callback = bonsai_progress_callback;
    params.progress_callback_user_data = const_cast<char *>(progress_path);

    persist_progress(progress_path, -1);

    mtmd_context * ctx = mtmd_init_from_file(
        path,
        text_model,
        params
    );

    if (ctx == nullptr) {
        persist_progress(progress_path, -2);
        return out;
    }

    persist_progress(progress_path, 101);
    out.supports_vision = mtmd_support_vision(ctx) ? 1 : 0;
    mtmd_free(ctx);

    out.ok = 1;
    persist_progress(progress_path, 102);
    return out;
}
