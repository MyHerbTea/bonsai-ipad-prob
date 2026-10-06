#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint64_t available_bytes;
    uint64_t resident_bytes;
    uint64_t virtual_bytes;
    uint64_t phys_footprint_bytes;
    uint64_t metal_allocated_bytes;
    uint64_t metal_recommended_bytes;
    int32_t has_unified_memory;
} BonsaiSystemProbe;

BonsaiSystemProbe BonsaiReadSystemProbe(void);
uint64_t BonsaiRelieveHeapPressure(void);

typedef struct {
    int32_t has_metal_device;
    int32_t supports_metal4_family;
    int32_t requested_metal_language_4;
    int32_t tensor_library_compiled;
    int32_t tensor_pipeline_compiled;
    int32_t failure_stage;
    int32_t framework_metal_registry_present;
    int32_t framework_embed_library;
    int64_t error_code;
    uint64_t duration_ns;
} BonsaiMetalTensorCapabilityProbe;

BonsaiMetalTensorCapabilityProbe BonsaiProbeMetalTensorCapability(void);

typedef struct {
    int32_t capture_started;
    int32_t log_observed;
    int32_t has_tensor;
    int32_t logger_restored;
} BonsaiMetalTensorBackendLogEvidence;

void BonsaiBeginMetalTensorBackendLogCapture(void);
BonsaiMetalTensorBackendLogEvidence BonsaiEndMetalTensorBackendLogCapture(void);

#ifdef __cplusplus
}
#endif
