#ifndef AEC_RUNTIME_H
#define AEC_RUNTIME_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct aec_context_t* aecContext;
typedef struct aec_module_t* aecModule;
typedef uint64_t aecDevicePtr;

typedef enum aec_error_t {
    AEC_SUCCESS = 0,
    AEC_ERROR_INVALID_VALUE = 1,
    AEC_ERROR_OUT_OF_MEMORY = 2,
    AEC_ERROR_NOT_INITIALIZED = 3,
    AEC_ERROR_UNSUPPORTED_FEATURE = 4,
    AEC_ERROR_ADDRESS_WINDOW_EXHAUSTED = 5,
    AEC_ERROR_ADDRESS_NOT_MAPPED = 6,
    AEC_ERROR_MODULE_INVALID = 7,
    AEC_ERROR_LAUNCH_FAILED = 8,
    AEC_ERROR_TIMEOUT = 9,
    AEC_ERROR_INTERNAL = 255
} aecError;

typedef enum aec_mem_place_t {
    AEC_MEM_AUTO = 0,
    AEC_MEM_HBM = 1,
    AEC_MEM_DDR = 2,
    AEC_MEM_EXPLICIT_BANK = 3
} aecMemPlace;

typedef struct aec_alloc_desc_t {
    size_t bytes;
    aecMemPlace placement;
    uint32_t bank_mask;
    uint32_t flags;
} aecAllocDesc;

typedef struct aec_dim3_t { uint32_t x, y, z; } aecDim3;

typedef struct aec_kernel_arg_t {
    const void* data;
    size_t bytes;
    uint32_t flags;
} aecKernelArg;

typedef struct aec_launch_desc_t {
    aecDim3 grid_dim;
    aecDim3 block_dim;
    uint32_t dynamic_smem_bytes;
    const aecKernelArg* args;
    uint32_t arg_count;
    uint32_t flags;
} aecLaunchDesc;

typedef struct aec_counters_t {
    uint64_t hbm_bytes, ddr_bytes, h2d_bytes, d2h_bytes;
    uint64_t kernel_launches, fallback_true, fallback_false, last_error;
} aecCounters;

typedef struct aec_capability_t {
    uint32_t isa_version_major, isa_version_minor;
    uint32_t logical_warp_width, physical_simd_lanes, issue_beats_per_warp;
    uint32_t supports_fp8_e4m3fn, supports_mma_m16n16k16_e4m3_f32;
    uint32_t supports_sfu_rcp_f32, supports_sfu_exp2_f32;
    uint32_t address_window_bits, max_windows, shared_memory_bytes_per_cu;
    uint32_t hbm_bank_count, ddr_bank_count;
} aecCapability;

#define AEC_KERNEL_ARG_DEVICE_PTR 0x1u
#define AEC_KERNEL_ARG_VALUE      0x2u
#define AEC_MEM_FLAG_HOT          0x1u
#define AEC_MEM_FLAG_COLD         0x2u
#define AEC_MEM_FLAG_KV_CACHE     0x4u
#define AEC_MEM_FLAG_WEIGHT       0x8u

const char* aecGetErrorString(aecError error);
aecError aecContextCreate(aecContext* out_ctx, int device_index);
aecError aecContextDestroy(aecContext ctx);
aecError aecGetCapability(aecContext ctx, aecCapability* out_capability);
aecError aecMalloc(aecContext ctx, aecDevicePtr* out_ptr, size_t bytes, const aecAllocDesc* desc);
aecError aecFree(aecContext ctx, aecDevicePtr ptr);
aecError aecMemcpyH2D(aecContext ctx, aecDevicePtr dst, const void* src, size_t bytes);
aecError aecMemcpyD2H(aecContext ctx, void* dst, aecDevicePtr src, size_t bytes);
aecError aecModuleLoad(aecContext ctx, aecModule* out_module, const char* aecbin_path, const char* manifest_json_path);
aecError aecModuleUnload(aecContext ctx, aecModule module);
aecError aecKernelLaunch(aecContext ctx, aecModule module, const char* kernel_name, const aecLaunchDesc* launch);
aecError aecSynchronize(aecContext ctx, uint32_t timeout_ms);
aecError aecGetLastError(aecContext ctx);
aecError aecReadCounters(aecContext ctx, aecCounters* out_counters);
aecError aecResetState(aecContext ctx, uint32_t reason_flags);
aecError aecTranslateDevicePtr(aecContext ctx, aecDevicePtr ptr, uint32_t* out_window_id, uint32_t* out_offset);

#ifdef __cplusplus
}
#endif

#endif
