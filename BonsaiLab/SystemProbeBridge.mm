#include "SystemProbeBridge.h"

#include <mach/mach.h>
#include <os/proc.h>
#import <Metal/Metal.h>

BonsaiSystemProbe BonsaiReadSystemProbe(void) {
    BonsaiSystemProbe out = {};
    out.available_bytes = os_proc_available_memory();

    id<MTLDevice> metal = MTLCreateSystemDefaultDevice();
    if (metal != nil) {
        out.metal_allocated_bytes = (uint64_t) metal.currentAllocatedSize;
        out.metal_recommended_bytes =
            (uint64_t) metal.recommendedMaxWorkingSetSize;
        out.has_unified_memory = metal.hasUnifiedMemory ? 1 : 0;
    }

    mach_task_basic_info_data_t basic = {};
    mach_msg_type_number_t basic_count = MACH_TASK_BASIC_INFO_COUNT;
    if (task_info(
        mach_task_self_,
        MACH_TASK_BASIC_INFO,
        reinterpret_cast<task_info_t>(&basic),
        &basic_count
    ) == KERN_SUCCESS) {
        out.resident_bytes = basic.resident_size;
        out.virtual_bytes = basic.virtual_size;
    }

    task_vm_info_data_t vm = {};
    mach_msg_type_number_t vm_count = TASK_VM_INFO_COUNT;
    if (task_info(
        mach_task_self_,
        TASK_VM_INFO,
        reinterpret_cast<task_info_t>(&vm),
        &vm_count
    ) == KERN_SUCCESS) {
        out.phys_footprint_bytes = vm.phys_footprint;
    }

    return out;
}
