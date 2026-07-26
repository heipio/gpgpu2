"""AEC-G v1.0 golden simulator utilities.

This module is intentionally small but strict about the numeric contract used by
stage-one RTL/compiler work: FP8 E4M3FN conversion, SFU RCP/EXP2 behavior, and
MMA.m16n16k16.e4m3.f32 accumulation order.
"""


import math
import struct

from typing import Dict, Iterable, List, MutableMapping, Optional, Sequence

CANONICAL_NAN_F32_BITS = 0x7FC00000
CANONICAL_NAN_F32 = struct.unpack("<f", struct.pack("<I", CANONICAL_NAN_F32_BITS))[0]
FP8_E4M3FN_CANONICAL_NAN = 0x7F
FP8_E4M3FN_MAX_POS = 0x7E
FP8_E4M3FN_MAX_NEG = 0xFE
FP8_E4M3FN_MAX_VALUE = 448.0
LOGICAL_WARP_WIDTH = 32


def f32(value: float) -> float:
    """Round a Python float to IEEE binary32 and return it as a Python float."""
    return struct.unpack("<f", struct.pack("<f", float(value)))[0]


def f32_bits(value: float) -> int:
    return struct.unpack("<I", struct.pack("<f", f32(value)))[0]


def bits_to_f32(bits: int) -> float:
    return struct.unpack("<f", struct.pack("<I", bits & 0xFFFFFFFF))[0]


def canonical_nan() -> float:
    return CANONICAL_NAN_F32


def _round_to_even_int(value: float) -> int:
    floor = math.floor(value)
    frac = value - floor
    if frac > 0.5:
        return floor + 1
    if frac < 0.5:
        return floor
    return floor if (floor & 1) == 0 else floor + 1


def fp8_e4m3fn_to_float(byte: int) -> float:
    """Decode one E4M3FN byte to f32.

    E4M3FN has finite values only, except the two canonical NaN encodings with
    exponent=15 and fraction=7. The maximum finite magnitude is 448.
    """
    b = byte & 0xFF
    sign = -1.0 if (b & 0x80) else 1.0
    exp = (b >> 3) & 0x0F
    frac = b & 0x07
    if exp == 0x0F and frac == 0x07:
        return canonical_nan()
    if exp == 0:
        value = (frac / 8.0) * (2.0 ** -6)
    else:
        value = (1.0 + frac / 8.0) * (2.0 ** (exp - 7))
    return f32(sign * value)


def float_to_fp8_e4m3fn(value: float) -> int:
    """Encode a Python/f32 value as E4M3FN with RNE and overflow saturation."""
    x = f32(value)
    bits = f32_bits(x)
    sign_bit = (bits >> 31) & 1
    sign_mask = sign_bit << 7

    if math.isnan(x):
        return FP8_E4M3FN_CANONICAL_NAN
    if x == 0.0:
        return sign_mask
    if math.isinf(x) or abs(x) >= FP8_E4M3FN_MAX_VALUE:
        return FP8_E4M3FN_MAX_NEG if sign_bit else FP8_E4M3FN_MAX_POS

    ax = abs(x)
    if ax < 2.0 ** -6:
        frac = _round_to_even_int(ax / (2.0 ** -9))
        if frac <= 0:
            return sign_mask
        if frac <= 7:
            return sign_mask | frac
        return sign_mask | 0x08

    exp_unbiased = math.floor(math.log(ax, 2.0))
    exp = int(exp_unbiased + 7)
    scaled = ax / (2.0 ** exp_unbiased) - 1.0
    frac = _round_to_even_int(scaled * 8.0)

    if frac == 8:
        frac = 0
        exp += 1
    if exp > 0x0F or (exp == 0x0F and frac > 0x06):
        return FP8_E4M3FN_MAX_NEG if sign_bit else FP8_E4M3FN_MAX_POS
    return sign_mask | ((exp & 0x0F) << 3) | (frac & 0x07)


def pack_fp8(values: Iterable[float]) -> List[int]:
    return [float_to_fp8_e4m3fn(v) for v in values]


def sfu_rcp_f32(value: float) -> float:
    """Golden RCP.f32 approximation model.

    The architectural RTL may approximate, but the golden model returns the
    correctly rounded reciprocal. That is within the required 2^-10 threshold
    and defines all special-value behavior.
    """
    x = f32(value)
    if math.isnan(x):
        return canonical_nan()
    if x == 0.0:
        return bits_to_f32(((f32_bits(x) >> 31) << 31) | 0x7F800000)
    if math.isinf(x):
        return bits_to_f32((f32_bits(x) >> 31) << 31)
    return f32(1.0 / x)


def sfu_exp2_f32(value: float) -> float:
    """Golden EXP2.f32 approximation model with required special behavior."""
    x = f32(value)
    if math.isnan(x):
        return canonical_nan()
    if x == math.inf:
        return math.inf
    if x == -math.inf:
        return 0.0
    if x > 127.0:
        return math.inf
    if x < -149.0:
        return 0.0
    return f32(2.0 ** x)


def rel_error(got: float, ref: float) -> float:
    if math.isnan(ref):
        return 0.0 if math.isnan(got) else math.inf
    if math.isinf(ref):
        return 0.0 if got == ref else math.inf
    denom = max(abs(ref), 2.0 ** -126)
    return abs(got - ref) / denom


def mma_m16n16k16_e4m3_f32(
    a_fp8: Sequence[Sequence[int]],
    b_fp8: Sequence[Sequence[int]],
    c_f32: Optional[Sequence[Sequence[float]]] = None,
) -> List[List[float]]:
    """Compute D = C + A*B for m16n16k16 using exact k=0..15 order.

    A is indexed [16][16] in FP8 bytes. B is indexed [16][16] in FP8 bytes.
    C, when omitted, is all +0.0. Each multiply is rounded to f32, then each
    accumulation step is rounded to f32, matching a conservative FP32 datapath.
    """
    if len(a_fp8) != 16 or len(b_fp8) != 16:
        raise ValueError("A and B must be 16x16 FP8 matrices")
    for row in list(a_fp8) + list(b_fp8):
        if len(row) != 16:
            raise ValueError("A and B must be 16x16 FP8 matrices")
    if c_f32 is not None and (len(c_f32) != 16 or any(len(row) != 16 for row in c_f32)):
        raise ValueError("C must be 16x16 f32 matrix")

    out: List[List[float]] = [[0.0 for _ in range(16)] for _ in range(16)]
    for m in range(16):
        for n in range(16):
            acc = f32(0.0 if c_f32 is None else c_f32[m][n])
            for k in range(16):
                prod = f32(fp8_e4m3fn_to_float(a_fp8[m][k]) * fp8_e4m3fn_to_float(b_fp8[k][n]))
                acc = f32(acc + prod)
            out[m][n] = acc
    return out


def reduce_add_f32_balanced(values: Sequence[float], active_mask: int = 0xFFFFFFFF) -> float:
    """AEC-G REDUCE.ADD.f32 order: ascending logical lanes, steps 1,2,4,..."""
    if len(values) != LOGICAL_WARP_WIDTH:
        raise ValueError("REDUCE.ADD expects 32 logical lane values")
    lane_vals = [f32(values[i]) if ((active_mask >> i) & 1) else f32(0.0) for i in range(LOGICAL_WARP_WIDTH)]
    step = 1
    while step < LOGICAL_WARP_WIDTH:
        next_vals = lane_vals[:]
        for lane in range(0, LOGICAL_WARP_WIDTH, step * 2):
            for i in range(step):
                lhs = lane + i
                rhs = lhs + step
                if rhs < LOGICAL_WARP_WIDTH:
                    next_vals[lhs] = f32(lane_vals[lhs] + lane_vals[rhs])
        lane_vals = next_vals
        step *= 2
    return lane_vals[0]



class AECGSimulator:
    """Minimal lane-state simulator used by early ISA tests."""

    def __init__(self, lanes: int = LOGICAL_WARP_WIDTH, gpr_count: int = 256, pred_count: int = 8, active_mask: int = 0xFFFFFFFF) -> None:
        if lanes != LOGICAL_WARP_WIDTH:
            raise ValueError("AEC-G v1.0 logical warp width is fixed at 32")
        self.lanes = lanes
        self.gpr_count = gpr_count
        self.pred_count = pred_count
        self.active_mask = active_mask
        self.gpr = [[0 for _ in range(self.gpr_count)] for _ in range(self.lanes)]
        self.pred = [[False for _ in range(self.pred_count)] for _ in range(self.lanes)]
        self.faults = []
        self.memory = {}

    def lane_active(self, lane: int, predicate: Optional[int] = None) -> bool:
        if ((self.active_mask >> lane) & 1) == 0:
            return False
        if predicate is None:
            return True
        return self.pred[lane][predicate]

    def write_gpr(self, lane: int, reg: int, value: int, predicate: Optional[int] = None) -> None:
        if self.lane_active(lane, predicate):
            self.gpr[lane][reg] = value & 0xFFFFFFFF

    def setp(self, dst_pred: int, lhs_reg: int, rhs_reg: int, cmp: str = "eq", predicate: Optional[int] = None) -> None:
        for lane in range(self.lanes):
            if not self.lane_active(lane, predicate):
                continue
            lhs = self.gpr[lane][lhs_reg]
            rhs = self.gpr[lane][rhs_reg]
            if cmp == "eq":
                result = lhs == rhs
            elif cmp == "ne":
                result = lhs != rhs
            elif cmp == "lt_u32":
                result = lhs < rhs
            else:
                raise ValueError(f"unsupported SETP comparison {cmp}")
            self.pred[lane][dst_pred] = result

    def sfu_rcp(self, dst: int, src: int, predicate: Optional[int] = None) -> None:
        for lane in range(self.lanes):
            if self.lane_active(lane, predicate):
                self.gpr[lane][dst] = f32_bits(sfu_rcp_f32(bits_to_f32(self.gpr[lane][src])))

    def sfu_exp2(self, dst: int, src: int, predicate: Optional[int] = None) -> None:
        for lane in range(self.lanes):
            if self.lane_active(lane, predicate):
                self.gpr[lane][dst] = f32_bits(sfu_exp2_f32(bits_to_f32(self.gpr[lane][src])))

    def mma(self, a: Sequence[Sequence[int]], b: Sequence[Sequence[int]], c: Optional[Sequence[Sequence[float]]] = None) -> List[List[float]]:
        return mma_m16n16k16_e4m3_f32(a, b, c)
