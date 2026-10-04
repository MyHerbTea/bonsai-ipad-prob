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
} FlashNextSystemProbe;

FlashNextSystemProbe FlashNextReadSystemProbe(void);

#ifdef __cplusplus
}
#endif
