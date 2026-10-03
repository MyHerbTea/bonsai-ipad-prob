#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

struct llama_model;

typedef struct {
    int32_t ok;
    int32_t supports_vision;
} BonsaiMTMDOnlyProbeResult;

BonsaiMTMDOnlyProbeResult BonsaiProbeMTMD(
    const char * path,
    const struct llama_model * text_model,
    bool use_gpu,
    int32_t image_max_tokens,
    const char * progress_path
);

#ifdef __cplusplus
}
#endif

#include "SystemProbeBridge.h"

#include "StagedVisionBridge.h"
