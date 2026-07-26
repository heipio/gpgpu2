"""PyTorch bridge for AEC runtime P0 operators.

The scoreable path must call the fixed runtime API. CPU fallback is debug-only
unless explicitly enabled, and every operator emits the required audit fields.
"""

import ctypes
import json
import os
import time
from collections import defaultdict

try:
    import torch
except Exception:
    torch = None

AEC_SUCCESS = 0
AEC_KERNEL_ARG_DEVICE_PTR = 0x1
AEC_KERNEL_ARG_VALUE = 0x2
AEC_MEM_AUTO, AEC_MEM_HBM, AEC_MEM_DDR = 0, 1, 2
AEC_MEM_FLAG_HOT, AEC_MEM_FLAG_COLD = 0x1, 0x2
AEC_MEM_FLAG_KV_CACHE, AEC_MEM_FLAG_WEIGHT = 0x4, 0x8


class AECError(RuntimeError):
    pass


class AECAllocDesc(ctypes.Structure):
    _fields_ = [("bytes", ctypes.c_size_t), ("placement", ctypes.c_int),
                ("bank_mask", ctypes.c_uint32), ("flags", ctypes.c_uint32)]


class FallbackLogger(object):
    def __init__(self, path=None):
        self.path = path or os.environ.get("AEC_FALLBACK_LOG")
        self.counts = defaultdict(int)
        self.records = []

    def record(self, operator, model, fallback, reason, cpu_time_s, input_bytes, output_bytes, scoreable_main_compute):
        key = (operator, model)
        self.counts[key] += 1
        rec = {
            "operator": operator,
            "model": model,
            "fallback": bool(fallback),
            "reason": reason,
            "cpu_time_s": float(cpu_time_s),
            "input_bytes": int(input_bytes),
            "output_bytes": int(output_bytes),
            "call_count": self.counts[key],
            "scoreable_main_compute": bool(scoreable_main_compute),
            "timestamp_ns": int(time.time() * 1000000000),
        }
        self.records.append(rec)
        if self.path:
            with open(self.path, "a") as fh:
                fh.write(json.dumps(rec, sort_keys=True) + "\n")
        return rec


class AECRuntime(object):
    def __init__(self, library_path=None, device_index=0):
        self.library_path = library_path or os.environ.get("AEC_RUNTIME_LIB")
        self.device_index = device_index
        self.lib = None
        self.ctx = ctypes.c_void_p()
        if self.library_path:
            self._load(self.library_path)

    @property
    def available(self):
        return self.lib is not None and bool(self.ctx.value)

    def _load(self, path):
        self.lib = ctypes.CDLL(path)
        self.lib.aecContextCreate.argtypes = [ctypes.POINTER(ctypes.c_void_p), ctypes.c_int]
        self.lib.aecContextCreate.restype = ctypes.c_int
        self.lib.aecMalloc.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint64), ctypes.c_size_t, ctypes.POINTER(AECAllocDesc)]
        self.lib.aecMalloc.restype = ctypes.c_int
        rc = self.lib.aecContextCreate(ctypes.byref(self.ctx), self.device_index)
        self._check(rc, "aecContextCreate")

    def _check(self, rc, where):
        if rc != AEC_SUCCESS:
            raise AECError("%s failed with AEC error %d" % (where, rc))

    def malloc(self, bytes_, placement=AEC_MEM_AUTO, flags=AEC_MEM_FLAG_HOT, bank_mask=0):
        if not self.available:
            raise AECError("AEC runtime library is not loaded")
        desc = AECAllocDesc(bytes_, placement, bank_mask, flags)
        out = ctypes.c_uint64()
        self._check(self.lib.aecMalloc(self.ctx, ctypes.byref(out), bytes_, ctypes.byref(desc)), "aecMalloc")
        return out.value


class AECTorch(object):
    def __init__(self, runtime=None, fallback_log=None, allow_debug_fallback=False, model_name="unknown"):
        self.runtime = runtime or AECRuntime()
        self.fallback_log = fallback_log or FallbackLogger()
        self.allow_debug_fallback = allow_debug_fallback
        self.model_name = model_name
        self.modules = {}

    def fp8_gemm(self, a_fp8, b_fp8, c=None, scale_a=1.0, scale_b=1.0, scoreable=True):
        input_bytes = nbytes(a_fp8) + nbytes(b_fp8) + nbytes(c)
        if self.runtime.available and "fp8_gemm" in self.modules:
            start = time.time()
            # TODO: copy tensors through aecMalloc/aecMemcpyH2D, launch compiled AEC kernel, D2H result.
            self.fallback_log.record("fp8_gemm", self.model_name, False, "aec_runtime_launch",
                                     time.time() - start, input_bytes, 0, scoreable)
            raise NotImplementedError("FP8 GEMM runtime launch awaits first AEC kernel module")
        if scoreable and not self.allow_debug_fallback:
            self.fallback_log.record("fp8_gemm", self.model_name, True,
                                     "runtime_unavailable_scoreable_fallback_blocked", 0.0,
                                     input_bytes, 0, True)
            raise AECError("scoreable FP8 GEMM cannot use CPU fallback")
        return self._cpu_fp8_gemm(a_fp8, b_fp8, c, scale_a, scale_b, input_bytes, scoreable)

    def add(self, a, b, scoreable=True):
        return self._cpu_binary("add", a, b, lambda x, y: x + y, scoreable)

    def mul(self, a, b, scoreable=True):
        return self._cpu_binary("mul", a, b, lambda x, y: x * y, scoreable)

    def relu(self, x, scoreable=True):
        return self._cpu_unary("relu", x, lambda t: torch.relu(t), scoreable)

    def reset_request_state(self, reason="request_boundary"):
        self.fallback_log.record("state_reset", self.model_name, False, reason, 0.0, 0, 0, False)
        # TODO: call aecResetState and clear KV/output/activation/input-derived buffers.

    def _cpu_fp8_gemm(self, a_fp8, b_fp8, c, scale_a, scale_b, input_bytes, scoreable):
        if torch is None:
            raise AECError("torch unavailable")
        start = time.time()
        a = decode_e4m3fn(a_fp8).float() * float(scale_a)
        b = decode_e4m3fn(b_fp8).float() * float(scale_b)
        out = torch.matmul(a, b)
        if c is not None:
            out = out + c.float()
        self.fallback_log.record("fp8_gemm", self.model_name, True, "debug_only_cpu_reference",
                                 time.time() - start, input_bytes, nbytes(out), scoreable)
        return out

    def _cpu_unary(self, name, x, fn, scoreable):
        if scoreable and not self.allow_debug_fallback:
            self.fallback_log.record(name, self.model_name, True, "runtime_unavailable_scoreable_fallback_blocked",
                                     0.0, nbytes(x), 0, True)
            raise AECError("scoreable %s cannot use CPU fallback" % name)
        start = time.time()
        out = fn(x)
        self.fallback_log.record(name, self.model_name, True, "debug_only_cpu_reference",
                                 time.time() - start, nbytes(x), nbytes(out), scoreable)
        return out

    def _cpu_binary(self, name, a, b, fn, scoreable):
        if scoreable and not self.allow_debug_fallback:
            self.fallback_log.record(name, self.model_name, True, "runtime_unavailable_scoreable_fallback_blocked",
                                     0.0, nbytes(a) + nbytes(b), 0, True)
            raise AECError("scoreable %s cannot use CPU fallback" % name)
        start = time.time()
        out = fn(a, b)
        self.fallback_log.record(name, self.model_name, True, "debug_only_cpu_reference",
                                 time.time() - start, nbytes(a) + nbytes(b), nbytes(out), scoreable)
        return out


def nbytes(x):
    if x is None:
        return 0
    if hasattr(x, "numel") and hasattr(x, "element_size"):
        return int(x.numel() * x.element_size())
    return len(x) if isinstance(x, (bytes, bytearray)) else 0


def decode_e4m3fn(x):
    if torch is None:
        raise AECError("torch unavailable")
    xi = x.to(torch.uint8)
    sign = torch.where((xi & 0x80) != 0, -1.0, 1.0)
    exp = ((xi >> 3) & 0x0F).to(torch.int16)
    frac = (xi & 0x07).float()
    normal = (1.0 + frac / 8.0) * torch.pow(torch.tensor(2.0, device=xi.device), (exp - 7).float())
    subnormal = (frac / 8.0) * (2.0 ** -6)
    value = torch.where(exp == 0, subnormal, normal) * sign
    nan_mask = (exp == 0x0F) & ((xi & 0x07) == 0x07)
    return torch.where(nan_mask, torch.full_like(value, float("nan")), value)


__all__ = ["AECError", "AECRuntime", "AECTorch", "FallbackLogger"]
