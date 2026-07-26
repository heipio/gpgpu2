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
AEC_OPCODE_BY_VALUE = {
    0x01: "ADD",
    0x02: "SUB.u32",
    0x03: "MUL",
    0x04: "MAD.f32",
    0x05: "FMA.f32",
    0x10: "AND.b32",
    0x11: "OR.b32",
    0x12: "XOR.b32",
    0x13: "NOT.b32",
    0x14: "SHL.b32",
    0x15: "SHR.b32",
    0x16: "SAR.b32",
    0x20: "SETP",
    0x21: "CMPP",
    0x22: "SEL",
    0x30: "LD",
    0x31: "ST",
    0x34: "FENCE",
    0x40: "BRA",
    0x41: "BRX",
    0x42: "SSY",
    0x43: "SYNC",
    0x44: "BAR.SYNC",
    0x45: "HALT",
    0x54: "CPY",
    0x55: "LOADI",
    0x56: "LOADI64",
    0x57: "CVT",
    0x58: "PACK",
    0x59: "UNPACK",
    0x60: "SHFL",
    0x61: "REDUCE.ADD.f32",
    0x70: "MMA.m16n16k16.e4m3.f32",
    0x80: "SFU",
    0xF0: "NOP",
}


def f32(value: float) -> float:
    """Round a Python float to IEEE binary32 and return it as a Python float."""
    return struct.unpack("<f", struct.pack("<f", float(value)))[0]


def f32_bits(value: float) -> int:
    return struct.unpack("<I", struct.pack("<f", f32(value)))[0]


def bits_to_f32(bits: int) -> float:
    return struct.unpack("<f", struct.pack("<I", bits & 0xFFFFFFFF))[0]


def decode_aec_instruction_words(blob: bytes, pc: int) -> Dict[str, int]:
    """Decode one 128-bit little-endian AEC instruction at instruction PC."""
    start = pc * 16
    if start + 16 > len(blob):
        raise ValueError("AEC PC out of range")
    w0, w1, w2, w3 = struct.unpack("<IIII", blob[start:start + 16])
    value = w0 | (w1 << 32) | (w2 << 64) | (w3 << 96)
    opcode = (value >> 112) & 0xFFFF
    pred_ctrl = (value >> 96) & 0xFFFF
    mnemonic = AEC_OPCODE_BY_VALUE.get(opcode, "ILLEGAL")
    if opcode == 0x80:
        subop = (pred_ctrl >> 8) & 0x7
        mnemonic = {0: "SFU.RCP.f32", 1: "SFU.EXP2.f32"}.get(subop, "SFU.RESERVED")
    return {
        "opcode": opcode,
        "mnemonic": mnemonic,
        "pred": pred_ctrl,
        "dst": (value >> 80) & 0xFFFF,
        "src1": (value >> 64) & 0xFFFF,
        "src2": (value >> 32) & 0xFFFFFFFF,
        "src3": value & 0xFFFFFFFF,
    }


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
    """AEC-G REDUCE.ADD.f32 order: ascending logical lanes, steps 1,2,4,...

    Inactive logical lanes are skipped. They must not inject +0.0 into the
    floating-point tree because +0.0 can change bit-level results such as -0.0
    and can perturb NaN propagation/canonicalization behavior.
    """
    if len(values) != LOGICAL_WARP_WIDTH:
        raise ValueError("REDUCE.ADD expects 32 logical lane values")
    lane_vals = [f32(values[i]) if ((active_mask >> i) & 1) else None for i in range(LOGICAL_WARP_WIDTH)]
    step = 1
    while step < LOGICAL_WARP_WIDTH:
        next_vals = lane_vals[:]
        for lane in range(0, LOGICAL_WARP_WIDTH, step * 2):
            for i in range(step):
                lhs = lane + i
                rhs = lhs + step
                if rhs < LOGICAL_WARP_WIDTH:
                    val_l = lane_vals[lhs]
                    val_r = lane_vals[rhs]
                    if val_l is None:
                        next_vals[lhs] = val_r
                    elif val_r is None:
                        next_vals[lhs] = val_l
                    else:
                        next_vals[lhs] = f32(val_l + val_r)
        lane_vals = next_vals
        step *= 2
    return lane_vals[0] if lane_vals[0] is not None else f32(0.0)

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
        self.pc = 0
        self.reconv_stack = []
        self.halted = False

    def lane_active(self, lane: int, predicate: Optional[int] = None, negate: bool = False) -> bool:
        if ((self.active_mask >> lane) & 1) == 0:
            return False
        if predicate is None:
            return True
        return self.pred[lane][predicate] ^ negate

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

    def push_reconvergence(self, reconv_pc: int, mask: Optional[int] = None) -> None:
        self.reconv_stack.append((reconv_pc, self.active_mask if mask is None else mask))

    def ssy(self, reconv_pc: int) -> None:
        self.push_reconvergence(reconv_pc)

    def sync(self) -> None:
        if not self.reconv_stack:
            self.faults.append("SIMT_STACK_FAULT")
            return
        self.pc, self.active_mask = self.reconv_stack.pop()

    def brx(self, predicate: int, target_pc: int, fallthrough_pc: int, negate: bool = False) -> None:
        taken_mask = 0
        fallthrough_mask = 0
        for lane in range(self.lanes):
            bit = 1 << lane
            if (self.active_mask & bit) == 0:
                continue
            if self.pred[lane][predicate] ^ negate:
                taken_mask |= bit
            else:
                fallthrough_mask |= bit
        if taken_mask and fallthrough_mask:
            self.push_reconvergence(fallthrough_pc, fallthrough_mask)
            self.active_mask = taken_mask
            self.pc = target_pc
        elif taken_mask:
            self.active_mask = taken_mask
            self.pc = target_pc
        else:
            self.active_mask = fallthrough_mask
            self.pc = fallthrough_pc

    def store_u32(self, addr: int, value: int) -> None:
        for i in range(4):
            self.memory[(addr + i) & 0xFFFFFFFF] = (value >> (8 * i)) & 0xFF

    def load_u32(self, addr: int) -> int:
        value = 0
        for i in range(4):
            value |= (self.memory.get((addr + i) & 0xFFFFFFFF, 0) & 0xFF) << (8 * i)
        return value & 0xFFFFFFFF

    def execute_aecbin(self, blob: bytes, max_steps: int = 10000) -> None:
        if len(blob) % 16:
            raise ValueError("AEC binary must be 128-bit aligned")
        self.pc = 0
        self.halted = False
        steps = 0
        while not self.halted and steps < max_steps:
            if self.pc < 0 or self.pc >= len(blob) // 16:
                self.faults.append("ILLEGAL_PC")
                break
            inst = decode_aec_instruction_words(blob, self.pc)
            old_pc = self.pc
            self._execute_decoded(inst)
            if self.pc == old_pc:
                self.pc += 1
            steps += 1
        if steps >= max_steps:
            self.faults.append("WATCHDOG_TIMEOUT")

    def _execute_decoded(self, inst: Dict[str, int]) -> None:
        m = inst["mnemonic"]
        pred = inst["pred"]
        pred_enable = ((pred >> 15) & 1) == 1
        pred_negate = ((pred >> 14) & 1) == 1
        imm_en = ((pred >> 7) & 1) == 1
        subop = (pred >> 8) & 0x7
        predicate = None if pred == 0xFFFF or not pred_enable else (pred & 0x7)
        if m == "NOP" or m == "FENCE":
            return
        if m == "HALT":
            self.halted = True
            return
        if m == "BRA":
            self.pc = inst["src2"]
            return
        if m == "BRX":
            if predicate is None:
                self.pc = inst["src2"]
            else:
                self.brx(predicate, inst["src2"], self.pc + 1, negate=pred_negate)
            return
        if m == "SSY":
            self.ssy(inst["src2"])
            return
        if m == "SYNC":
            self.sync()
            return
        for lane in range(self.lanes):
            if not self.lane_active(lane, predicate, negate=pred_negate):
                continue
            if m == "CPY":
                if inst["src1"] == 0x0100:
                    self.gpr[lane][inst["dst"]] = lane
                else:
                    self.gpr[lane][inst["dst"]] = self.gpr[lane][inst["src1"]]
            elif m == "LOADI":
                self.gpr[lane][inst["dst"]] = inst["src2"]
            elif m == "ADD":
                rhs = inst["src2"] if imm_en else self.gpr[lane][inst["src2"]]
                self.gpr[lane][inst["dst"]] = (self.gpr[lane][inst["src1"]] + rhs) & 0xFFFFFFFF
            elif m == "MUL":
                rhs = inst["src2"] if imm_en else self.gpr[lane][inst["src2"]]
                self.gpr[lane][inst["dst"]] = (self.gpr[lane][inst["src1"]] * rhs) & 0xFFFFFFFF
            elif m == "SUB.u32":
                rhs = inst["src2"] if imm_en else self.gpr[lane][inst["src2"]]
                self.gpr[lane][inst["dst"]] = (self.gpr[lane][inst["src1"]] - rhs) & 0xFFFFFFFF
            elif m == "AND.b32":
                rhs = inst["src2"] if imm_en else self.gpr[lane][inst["src2"]]
                self.gpr[lane][inst["dst"]] = self.gpr[lane][inst["src1"]] & rhs
            elif m == "OR.b32":
                rhs = inst["src2"] if imm_en else self.gpr[lane][inst["src2"]]
                self.gpr[lane][inst["dst"]] = self.gpr[lane][inst["src1"]] | rhs
            elif m == "XOR.b32":
                rhs = inst["src2"] if imm_en else self.gpr[lane][inst["src2"]]
                self.gpr[lane][inst["dst"]] = self.gpr[lane][inst["src1"]] ^ rhs
            elif m == "SHL.b32":
                rhs = inst["src2"] if imm_en else self.gpr[lane][inst["src2"]]
                self.gpr[lane][inst["dst"]] = (self.gpr[lane][inst["src1"]] << (rhs & 31)) & 0xFFFFFFFF
            elif m == "SHR.b32":
                rhs = inst["src2"] if imm_en else self.gpr[lane][inst["src2"]]
                self.gpr[lane][inst["dst"]] = (self.gpr[lane][inst["src1"]] >> (rhs & 31)) & 0xFFFFFFFF
            elif m == "SFU.RCP.f32":
                self.gpr[lane][inst["dst"]] = sfu_rcp_bits(self.gpr[lane][inst["src1"]])
            elif m == "SFU.EXP2.f32":
                self.gpr[lane][inst["dst"]] = sfu_exp2_bits(self.gpr[lane][inst["src1"]])
            elif m == "LD":
                width_code = inst["src3"] & 0xFF
                if width_code != 2:
                    self.faults.append("UNSUPPORTED_WIDTH")
                    continue
                addr = (self.gpr[lane][inst["src1"]] + inst["src2"]) & 0xFFFFFFFF
                self.gpr[lane][inst["dst"]] = self.load_u32(addr)
            elif m == "ST":
                width_code = inst["src3"] & 0xFF
                src = (inst["src3"] >> 16) & 0xFFFF
                if width_code != 2:
                    self.faults.append("UNSUPPORTED_WIDTH")
                    continue
                addr = (self.gpr[lane][inst["src1"]] + inst["src2"]) & 0xFFFFFFFF
                self.store_u32(addr, self.gpr[lane][src])
            elif m == "SETP":
                cmp_code = subop
                lhs = self.gpr[lane][inst["src1"]]
                rhs = self.gpr[lane][inst["src2"]]
                self.pred[lane][inst["dst"]] = (lhs == rhs) if cmp_code == 0 else (lhs != rhs)
            else:
                self.faults.append("ILLEGAL_INSTRUCTION")
