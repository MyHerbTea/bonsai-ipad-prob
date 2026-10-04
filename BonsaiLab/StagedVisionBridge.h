#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int32_t code;
    int32_t prompt_tokens;
    int32_t image_tokens;
    int32_t projection_dim;
    int32_t generated_tokens;
    int32_t final_position;
    int32_t input_positions;
    int32_t requested_max_tokens;
    int32_t effective_max_tokens;
    int32_t accelerated_mode;
    int32_t cache_hit;
    int32_t resident_model_hit;
    int32_t resident_context_hit;
    int32_t kv_reuse_hit;
    uint64_t cache_bytes;
    double image_encode_ms;
    double full_model_load_ms;
    double context_create_ms;
    double generation_ms;
} BonsaiStagedVisionResult;

typedef void (*BonsaiStagedStreamCallback)(
    const char * utf8_bytes,
    size_t length,
    void * user_data
);


typedef struct {
    int32_t code;
    int32_t cache_hit;
    int32_t image_tokens;
    int32_t projection_dim;
    uint64_t cache_bytes;
    double image_encode_ms;
} BonsaiVisionCacheResult;

typedef struct {
    int32_t code;
    int32_t prompt_tokens;
    int32_t image_tokens;
    int32_t projection_dim;
    int32_t input_positions;
    int32_t prefix_positions;
    int32_t prefix_reuse_hit;
    double prefill_ms;
    double prefix_text_ms;
    double image_prefill_ms;
    double suffix_prefill_ms;
    int32_t suffix_token_count;
    int32_t suffix_decode_calls;
    int32_t suffix_batch_capacity;
    int32_t suffix_last_batch_tokens;
    double suffix_batch_utilization;
} BonsaiVisionPrefillResult;

int32_t BonsaiVisionCacheIsValid(
    const char * cache_path,
    int32_t image_max_tokens
);

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
);

BonsaiVisionCacheResult BonsaiPrepareVisionCache(
    const char * model_path,
    const char * mmproj_path,
    const char * image_path,
    int32_t image_max_tokens,
    const char * cache_path,
    char * out_error,
    size_t out_error_cap,
    const char * stage_path
);

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
);

int32_t BonsaiRetainVisionPrefixKV(
    struct llama_context * ctx,
    int32_t prefix_positions
);

void BonsaiReleaseStagedResidentModel(void);

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
);

#ifdef __cplusplus
}
#endif
