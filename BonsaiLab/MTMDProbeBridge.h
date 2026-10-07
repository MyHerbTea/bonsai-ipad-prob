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

// Returns 1=true, 0=false/not granted, -1=runtime probe unavailable.
// Uses runtime symbol lookup so the iOS Swift SDK does not need to expose
// SecTaskCreateFromSelf / SecTaskCopyValueForEntitlement declarations.
int32_t BonsaiEffectiveEntitlementFlag(const char * key);

#ifdef __cplusplus
}
#endif

#include "SystemProbeBridge.h"

#include "StagedVisionBridge.h"
