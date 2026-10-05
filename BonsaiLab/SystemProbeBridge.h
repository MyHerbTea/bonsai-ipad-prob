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

#ifdef __cplusplus
}
#endif


uint64_t BonsaiRelieveHeapPressure(void);
