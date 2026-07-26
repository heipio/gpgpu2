#include "aec_runtime.h"

#include <algorithm>
#include <cstring>
#include <fstream>
#include <map>
#include <new>
#include <string>
#include <vector>

namespace {
const uint64_t kMagic = 0xAEC0000000000000ull;
const uint64_t kMagicMask = 0xFFF0000000000000ull;
const uint32_t kWindowBits = 32;
const uint64_t kWindowSize = 1ull << kWindowBits;
const uint32_t kMaxWindows = 1024;
const size_t kHbmSoftLimit = 8ull * 1024ull * 1024ull * 1024ull;
const size_t kLargeColdThreshold = 256ull * 1024ull * 1024ull;

struct Allocation {
    aecDevicePtr ptr;
    uint32_t window_id;
    size_t bytes;
    aecMemPlace placement;
    uint32_t bank_mask;
    std::vector<unsigned char> shadow;
};

static aecDevicePtr make_ptr(uint32_t window_id) {
    return kMagic | (static_cast<uint64_t>(window_id) << 32);
}

static bool read_file(const char* path, std::vector<unsigned char>* out) {
    std::ifstream f(path, std::ios::binary);
    if (!f) return false;
    f.seekg(0, std::ios::end);
    std::streamoff sz = f.tellg();
    if (sz < 0) return false;
    f.seekg(0, std::ios::beg);
    out->resize(static_cast<size_t>(sz));
    if (sz) f.read(reinterpret_cast<char*>(&(*out)[0]), sz);
    return static_cast<bool>(f) || sz == 0;
}
}

struct aec_context_t {
    explicit aec_context_t(int index) : device_index(index), last_error(AEC_SUCCESS), next_window(1), hbm_used(0), ddr_used(0) {
        std::memset(&counters, 0, sizeof(counters));
        capability.isa_version_major = 1;
        capability.isa_version_minor = 0;
        capability.logical_warp_width = 32;
        capability.physical_simd_lanes = 8;
        capability.issue_beats_per_warp = 4;
        capability.supports_fp8_e4m3fn = 1;
        capability.supports_mma_m16n16k16_e4m3_f32 = 1;
        capability.supports_sfu_rcp_f32 = 1;
        capability.supports_sfu_exp2_f32 = 1;
        capability.address_window_bits = kWindowBits;
        capability.max_windows = kMaxWindows;
        capability.shared_memory_bytes_per_cu = 16u * 1024u;
        capability.hbm_bank_count = 32;
        capability.ddr_bank_count = 2;
    }
    int device_index;
    aecError last_error;
    uint32_t next_window;
    size_t hbm_used, ddr_used;
    aecCounters counters;
    aecCapability capability;
    std::map<aecDevicePtr, Allocation> allocations;
};

struct aec_module_t {
    std::vector<unsigned char> aecbin;
    std::string manifest;
};

static aecError set_error(aecContext ctx, aecError err) {
    if (ctx) {
        ctx->last_error = err;
        ctx->counters.last_error = static_cast<uint64_t>(err);
    }
    return err;
}

static Allocation* find_alloc(aecContext ctx, aecDevicePtr ptr) {
    if (!ctx || (ptr & kMagicMask) != kMagic) return 0;
    uint32_t window = static_cast<uint32_t>((ptr >> 32) & 0xFFFFFu);
    std::map<aecDevicePtr, Allocation>::iterator it = ctx->allocations.find(make_ptr(window));
    return it == ctx->allocations.end() ? 0 : &it->second;
}

static aecMemPlace choose_place(aecContext ctx, size_t bytes, const aecAllocDesc* desc) {
    if (desc && desc->placement != AEC_MEM_AUTO) return desc->placement;
    uint32_t flags = desc ? desc->flags : 0;
    if (flags & (AEC_MEM_FLAG_HOT | AEC_MEM_FLAG_KV_CACHE)) return AEC_MEM_HBM;
    if (flags & (AEC_MEM_FLAG_COLD | AEC_MEM_FLAG_WEIGHT)) return AEC_MEM_DDR;
    if (bytes >= kLargeColdThreshold && ctx->hbm_used + bytes > kHbmSoftLimit) return AEC_MEM_DDR;
    return AEC_MEM_HBM;
}

const char* aecGetErrorString(aecError error) {
    switch (error) {
    case AEC_SUCCESS: return "AEC_SUCCESS";
    case AEC_ERROR_INVALID_VALUE: return "AEC_ERROR_INVALID_VALUE";
    case AEC_ERROR_OUT_OF_MEMORY: return "AEC_ERROR_OUT_OF_MEMORY";
    case AEC_ERROR_NOT_INITIALIZED: return "AEC_ERROR_NOT_INITIALIZED";
    case AEC_ERROR_UNSUPPORTED_FEATURE: return "AEC_ERROR_UNSUPPORTED_FEATURE";
    case AEC_ERROR_ADDRESS_WINDOW_EXHAUSTED: return "AEC_ERROR_ADDRESS_WINDOW_EXHAUSTED";
    case AEC_ERROR_ADDRESS_NOT_MAPPED: return "AEC_ERROR_ADDRESS_NOT_MAPPED";
    case AEC_ERROR_MODULE_INVALID: return "AEC_ERROR_MODULE_INVALID";
    case AEC_ERROR_LAUNCH_FAILED: return "AEC_ERROR_LAUNCH_FAILED";
    case AEC_ERROR_TIMEOUT: return "AEC_ERROR_TIMEOUT";
    default: return "AEC_ERROR_INTERNAL";
    }
}

aecError aecContextCreate(aecContext* out_ctx, int device_index) {
    if (!out_ctx || device_index < 0) return AEC_ERROR_INVALID_VALUE;
    *out_ctx = new (std::nothrow) aec_context_t(device_index);
    return *out_ctx ? AEC_SUCCESS : AEC_ERROR_OUT_OF_MEMORY;
}

aecError aecContextDestroy(aecContext ctx) {
    if (!ctx) return AEC_ERROR_INVALID_VALUE;
    delete ctx;
    return AEC_SUCCESS;
}

aecError aecGetCapability(aecContext ctx, aecCapability* out) {
    if (!ctx || !out) return set_error(ctx, AEC_ERROR_INVALID_VALUE);
    *out = ctx->capability;
    return set_error(ctx, AEC_SUCCESS);
}

aecError aecMalloc(aecContext ctx, aecDevicePtr* out_ptr, size_t bytes, const aecAllocDesc* desc) {
    if (!ctx || !out_ptr || bytes == 0) return set_error(ctx, AEC_ERROR_INVALID_VALUE);
    if (bytes > kWindowSize) return set_error(ctx, AEC_ERROR_UNSUPPORTED_FEATURE);
    if (ctx->next_window >= kMaxWindows) return set_error(ctx, AEC_ERROR_ADDRESS_WINDOW_EXHAUSTED);
    Allocation a;
    a.window_id = ctx->next_window++;
    a.ptr = make_ptr(a.window_id);
    a.bytes = bytes;
    a.placement = choose_place(ctx, bytes, desc);
    a.bank_mask = desc ? desc->bank_mask : 0;
    try { a.shadow.resize(bytes); } catch (...) { return set_error(ctx, AEC_ERROR_OUT_OF_MEMORY); }
    if (a.placement == AEC_MEM_DDR) { ctx->ddr_used += bytes; ctx->counters.ddr_bytes += bytes; }
    else { ctx->hbm_used += bytes; ctx->counters.hbm_bytes += bytes; }
    ctx->allocations[a.ptr] = a;
    *out_ptr = a.ptr;
    return set_error(ctx, AEC_SUCCESS);
}

aecError aecFree(aecContext ctx, aecDevicePtr ptr) {
    if (!ctx) return AEC_ERROR_INVALID_VALUE;
    Allocation* a = find_alloc(ctx, ptr);
    if (!a) return set_error(ctx, AEC_ERROR_ADDRESS_NOT_MAPPED);
    aecDevicePtr base = make_ptr(a->window_id);
    ctx->allocations.erase(base);
    return set_error(ctx, AEC_SUCCESS);
}

aecError aecTranslateDevicePtr(aecContext ctx, aecDevicePtr ptr, uint32_t* out_window_id, uint32_t* out_offset) {
    if (!ctx || !out_window_id || !out_offset) return set_error(ctx, AEC_ERROR_INVALID_VALUE);
    Allocation* a = find_alloc(ctx, ptr);
    if (!a) return set_error(ctx, AEC_ERROR_ADDRESS_NOT_MAPPED);
    uint32_t off = static_cast<uint32_t>(ptr & 0xFFFFFFFFu);
    if (off > a->bytes) return set_error(ctx, AEC_ERROR_ADDRESS_NOT_MAPPED);
    *out_window_id = a->window_id;
    *out_offset = off;
    return set_error(ctx, AEC_SUCCESS);
}

aecError aecMemcpyH2D(aecContext ctx, aecDevicePtr dst, const void* src, size_t bytes) {
    if (!ctx || !src) return set_error(ctx, AEC_ERROR_INVALID_VALUE);
    Allocation* a = find_alloc(ctx, dst);
    if (!a) return set_error(ctx, AEC_ERROR_ADDRESS_NOT_MAPPED);
    uint32_t off = static_cast<uint32_t>(dst & 0xFFFFFFFFu);
    if (off + bytes > a->bytes) return set_error(ctx, AEC_ERROR_INVALID_VALUE);
    std::memcpy(&a->shadow[off], src, bytes);
    ctx->counters.h2d_bytes += bytes;
    return set_error(ctx, AEC_SUCCESS);
}

aecError aecMemcpyD2H(aecContext ctx, void* dst, aecDevicePtr src, size_t bytes) {
    if (!ctx || !dst) return set_error(ctx, AEC_ERROR_INVALID_VALUE);
    Allocation* a = find_alloc(ctx, src);
    if (!a) return set_error(ctx, AEC_ERROR_ADDRESS_NOT_MAPPED);
    uint32_t off = static_cast<uint32_t>(src & 0xFFFFFFFFu);
    if (off + bytes > a->bytes) return set_error(ctx, AEC_ERROR_INVALID_VALUE);
    std::memcpy(dst, &a->shadow[off], bytes);
    ctx->counters.d2h_bytes += bytes;
    return set_error(ctx, AEC_SUCCESS);
}

aecError aecModuleLoad(aecContext ctx, aecModule* out_module, const char* aecbin_path, const char* manifest_json_path) {
    if (!ctx || !out_module || !aecbin_path) return set_error(ctx, AEC_ERROR_INVALID_VALUE);
    std::vector<unsigned char> bin;
    if (!read_file(aecbin_path, &bin) || bin.empty() || (bin.size() % 16) != 0) return set_error(ctx, AEC_ERROR_MODULE_INVALID);
    aec_module_t* m = new (std::nothrow) aec_module_t();
    if (!m) return set_error(ctx, AEC_ERROR_OUT_OF_MEMORY);
    m->aecbin.swap(bin);
    if (manifest_json_path) {
        std::vector<unsigned char> manifest;
        if (read_file(manifest_json_path, &manifest) && !manifest.empty()) {
            m->manifest.assign(reinterpret_cast<const char*>(&manifest[0]), manifest.size());
            if (m->manifest.find("b128") != std::string::npos) {
                delete m;
                return set_error(ctx, AEC_ERROR_UNSUPPORTED_FEATURE);
            }
        }
    }
    *out_module = m;
    return set_error(ctx, AEC_SUCCESS);
}

aecError aecModuleUnload(aecContext ctx, aecModule module) {
    if (!ctx || !module) return set_error(ctx, AEC_ERROR_INVALID_VALUE);
    delete module;
    return set_error(ctx, AEC_SUCCESS);
}

aecError aecKernelLaunch(aecContext ctx, aecModule module, const char* kernel_name, const aecLaunchDesc* launch) {
    if (!ctx || !module || !kernel_name || !launch || (!launch->args && launch->arg_count)) return set_error(ctx, AEC_ERROR_INVALID_VALUE);
    if (launch->block_dim.x == 0 || launch->block_dim.x % ctx->capability.logical_warp_width != 0) return set_error(ctx, AEC_ERROR_INVALID_VALUE);
    if (launch->dynamic_smem_bytes > ctx->capability.shared_memory_bytes_per_cu) return set_error(ctx, AEC_ERROR_UNSUPPORTED_FEATURE);
    for (uint32_t i = 0; i < launch->arg_count; ++i) {
        const aecKernelArg& arg = launch->args[i];
        if (arg.flags & AEC_KERNEL_ARG_DEVICE_PTR) {
            if (!arg.data || arg.bytes != sizeof(aecDevicePtr)) return set_error(ctx, AEC_ERROR_INVALID_VALUE);
            aecDevicePtr ptr = 0;
            std::memcpy(&ptr, arg.data, sizeof(ptr));
            uint32_t w = 0, o = 0;
            aecError err = aecTranslateDevicePtr(ctx, ptr, &w, &o);
            if (err != AEC_SUCCESS) return err;
        }
    }
    // TODO: submit XDMA command queue packet and launch descriptor once RTL ABI lands.
    ctx->counters.kernel_launches += 1;
    return set_error(ctx, AEC_SUCCESS);
}

aecError aecSynchronize(aecContext ctx, uint32_t timeout_ms) {
    if (!ctx) return AEC_ERROR_INVALID_VALUE;
    (void)timeout_ms;
    // TODO: poll completion queue and run cache flush/invalidate policy.
    return set_error(ctx, AEC_SUCCESS);
}

aecError aecGetLastError(aecContext ctx) { return ctx ? ctx->last_error : AEC_ERROR_NOT_INITIALIZED; }

aecError aecReadCounters(aecContext ctx, aecCounters* out) {
    if (!ctx || !out) return set_error(ctx, AEC_ERROR_INVALID_VALUE);
    *out = ctx->counters;
    return set_error(ctx, AEC_SUCCESS);
}

aecError aecResetState(aecContext ctx, uint32_t reason_flags) {
    if (!ctx) return AEC_ERROR_INVALID_VALUE;
    (void)reason_flags;
    // TODO: clear activation/output/input-derived caches and LLM KV cache at phase boundaries.
    return set_error(ctx, AEC_SUCCESS);
}
