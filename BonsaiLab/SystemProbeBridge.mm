#include "SystemProbeBridge.h"

#include <mach/mach.h>
#include <mach/mach_time.h>
#include <os/proc.h>
#import <Metal/Metal.h>
#include <malloc/malloc.h>
#include <cstring>

#include <llama/ggml-backend.h>

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


extern "C" uint64_t BonsaiRelieveHeapPressure(void) {
    return (uint64_t) malloc_zone_pressure_relief(NULL, 0);
}


static uint64_t bonsai_elapsed_ns(uint64_t start, uint64_t end) {
    mach_timebase_info_data_t info = {};
    mach_timebase_info(&info);
    return (end - start) * (uint64_t) info.numer / (uint64_t) info.denom;
}

extern "C" BonsaiMetalTensorCapabilityProbe BonsaiProbeMetalTensorCapability(void) {
    BonsaiMetalTensorCapabilityProbe out = {};
    out.framework_embed_library = -1;

    ggml_backend_reg_t metal_reg = ggml_backend_reg_by_name("MTL");
    if (metal_reg != nullptr) {
        out.framework_metal_registry_present = 1;
        auto get_features = reinterpret_cast<ggml_backend_get_features_t>(
            ggml_backend_reg_get_proc_address(
                metal_reg,
                "ggml_backend_get_features"
            )
        );
        if (get_features != nullptr) {
            struct ggml_backend_feature * features = get_features(metal_reg);
            if (features != nullptr) {
                out.framework_embed_library = 0;
                for (size_t i = 0; features[i].name != nullptr; ++i) {
                    if (std::strcmp(features[i].name, "EMBED_LIBRARY") == 0
                        && features[i].value != nullptr
                        && std::strcmp(features[i].value, "1") == 0) {
                        out.framework_embed_library = 1;
                        break;
                    }
                }
            }
        }
    }

    id<MTLDevice> metal = MTLCreateSystemDefaultDevice();
    if (metal == nil) {
        out.failure_stage = 1;
        return out;
    }
    out.has_metal_device = 1;

    if (![metal supportsFamily:(MTLGPUFamily) 5002]) {
        out.failure_stage = 2;
        return out;
    }
    out.supports_metal4_family = 1;

    const uint64_t started = mach_absolute_time();
    MTLCompileOptions * options = [[MTLCompileOptions alloc] init];
    options.languageVersion = (MTLLanguageVersion) (4u << 16);
    out.requested_metal_language_4 = 1;

    NSString * source =
        @"#include <metal_stdlib>\n"
         "#include <metal_tensor>\n"
         "#include <MetalPerformancePrimitives/MetalPerformancePrimitives.h>\n"
         "using namespace metal;\n"
         "using namespace mpp::tensor_ops;\n"
         "kernel void bonsai_tensor_probe(\n"
         "  tensor<device half, dextents<int32_t, 2>> A [[buffer(0)]],\n"
         "  tensor<device half, dextents<int32_t, 2>> B [[buffer(1)]],\n"
         "  device float * C [[buffer(2)]],\n"
         "  uint2 tgid [[threadgroup_position_in_grid]]) {\n"
         "  auto a = A.slice(0, (int)tgid.y);\n"
         "  auto b = B.slice((int)tgid.x, 0);\n"
         "  matmul2d<matmul2d_descriptor(16, 16, dynamic_extent),\n"
         "    execution_simdgroups<4>> mm;\n"
         "  auto dst = mm.get_destination_cooperative_tensor<\n"
         "    decltype(a), decltype(b), float>();\n"
         "  mm.run(b.slice(0, 0), a.slice(0, 0), dst);\n"
         "  auto c = tensor<device float, dextents<int32_t, 2>, tensor_inline>(\n"
         "    C, dextents<int32_t, 2>(16, 16));\n"
         "  dst.store(c);\n"
         "}\n";

    NSError * library_error = nil;
    id<MTLLibrary> library = [metal newLibraryWithSource:source
                                                 options:options
                                                   error:&library_error];
    if (library == nil) {
        out.failure_stage = 3;
        out.error_code = library_error != nil ? (int64_t) library_error.code : -1;
        out.duration_ns = bonsai_elapsed_ns(started, mach_absolute_time());
        return out;
    }
    out.tensor_library_compiled = 1;

    id<MTLFunction> function = [library newFunctionWithName:@"bonsai_tensor_probe"];
    if (function == nil) {
        out.failure_stage = 4;
        out.error_code = -2;
        out.duration_ns = bonsai_elapsed_ns(started, mach_absolute_time());
        return out;
    }

    NSError * pipeline_error = nil;
    id<MTLComputePipelineState> pipeline =
        [metal newComputePipelineStateWithFunction:function error:&pipeline_error];
    if (pipeline == nil) {
        out.failure_stage = 5;
        out.error_code = pipeline_error != nil ? (int64_t) pipeline_error.code : -3;
        out.duration_ns = bonsai_elapsed_ns(started, mach_absolute_time());
        return out;
    }

    out.tensor_pipeline_compiled = 1;
    out.duration_ns = bonsai_elapsed_ns(started, mach_absolute_time());
    return out;
}
