#!/usr/bin/env python3
"""Generate and validate AEC-G SFU approximation LUTs.

Contract thresholds are relative error gates from AEC-G v1.0:
  RCP.f32  max relative error <= 2^-10
  EXP2.f32 max relative error <= 2^-9 in normal result range
"""

import argparse
import math
import random
import struct
from pathlib import Path
from typing import Iterable, List, Tuple


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_RCP_MEM = ROOT / "rtl" / "sfu_rcp_lut.mem"
DEFAULT_EXP2_MEM = ROOT / "rtl" / "sfu_exp2_lut.mem"
RCP_REL_LIMIT = 2.0 ** -10
EXP2_REL_LIMIT = 2.0 ** -9
CANONICAL_NAN = 0x7FC00000


def f32_to_bits(x: float) -> int:
    try:
        return struct.unpack("<I", struct.pack("<f", float(x)))[0]
    except OverflowError:
        return 0xFF800000 if math.copysign(1.0, x) < 0.0 else 0x7F800000


def bits_to_f32(bits: int) -> float:
    return struct.unpack("<f", struct.pack("<I", bits & 0xFFFFFFFF))[0]


def f32(x: float) -> float:
    return bits_to_f32(f32_to_bits(x))


def rne_int(x: float) -> int:
    floor = math.floor(x)
    frac = x - floor
    if frac > 0.5:
        return floor + 1
    if frac < 0.5:
        return floor
    return floor if (floor & 1) == 0 else floor + 1


def build_rcp_lut(lut_bits: int) -> List[int]:
    entries = 1 << lut_bits
    out: List[int] = []
    for idx in range(entries):
        m = 1.0 + (idx + 0.5) / entries
        y = 2.0 / m
        mant = rne_int((y - 1.0) * (1 << 23))
        out.append(max(0, min((1 << 23) - 1, mant)))
    return out


def build_exp2_lut(lut_bits: int) -> List[int]:
    entries = 1 << lut_bits
    out: List[int] = []
    for idx in range(entries):
        y = 2.0 ** (idx / entries)
        mant = rne_int((y - 1.0) * (1 << 23))
        out.append(max(0, min((1 << 23) - 1, mant)))
    return out


def write_mem(path: Path, lut: Iterable[int]) -> None:
    path.write_text("".join(f"{value:06x}\n" for value in lut), encoding="ascii")


def normalize_f32_bits(bits: int) -> Tuple[int, int, int]:
    exp = (bits >> 23) & 0xFF
    frac = bits & 0x7FFFFF
    if exp == 0:
        if frac == 0:
            return 0, 0, 0
        mant = frac
        eff_exp = 1
        while (mant & (1 << 23)) == 0:
            mant <<= 1
            eff_exp -= 1
        return eff_exp, mant & 0xFFFFFF, 1
    return exp, (1 << 23) | frac, 1


def model_rcp_bits(bits: int, lut: List[int], lut_bits: int) -> int:
    sign = bits & 0x80000000
    exp = (bits >> 23) & 0xFF
    frac = bits & 0x7FFFFF
    if exp == 0xFF and frac != 0:
        return CANONICAL_NAN
    if exp == 0 and frac == 0:
        return sign | 0x7F800000
    if exp == 0xFF:
        return sign
    eff_exp, mant, valid = normalize_f32_bits(bits)
    if not valid:
        return sign | 0x7F800000
    idx = (mant >> (23 - lut_bits)) & ((1 << lut_bits) - 1)
    out_exp = 253 - eff_exp
    if out_exp >= 255:
        return sign | 0x7F800000
    if out_exp <= 0:
        shift = 1 - out_exp
        sig = (1 << 23) | lut[idx]
        frac_out = 0 if shift >= 24 else (sig >> shift)
        return sign | frac_out
    return sign | ((out_exp & 0xFF) << 23) | lut[idx]


def f32_to_q_trunc(bits: int, frac_bits: int) -> int:
    sign = (bits >> 31) & 1
    exp = (bits >> 23) & 0xFF
    frac = bits & 0x7FFFFF
    if exp == 0:
        return 0
    mant = (1 << 23) | frac
    shift = exp - 127 - 23 + frac_bits
    mag = mant << shift if shift >= 0 else mant >> (-shift)
    return -mag if sign else mag


def model_exp2_bits(bits: int, lut: List[int], lut_bits: int) -> int:
    sign = (bits >> 31) & 1
    exp = (bits >> 23) & 0xFF
    frac = bits & 0x7FFFFF
    if exp == 0xFF and frac != 0:
        return CANONICAL_NAN
    if bits == 0x7F800000:
        return 0x7F800000
    if bits == 0xFF800000:
        return 0
    if (bits & 0x7FFFFFFF) == 0:
        return 0x3F800000
    x_abs = bits & 0x7FFFFFFF
    if sign == 0 and x_abs >= 0x43000000:
        return 0x7F800000
    if sign == 1 and x_abs > 0x42FC0000:
        return 0
    q = f32_to_q_trunc(bits, lut_bits)
    whole = q >> lut_bits
    idx = q & ((1 << lut_bits) - 1)
    out_exp = whole + 127
    if out_exp >= 255:
        return 0x7F800000
    if out_exp <= 0:
        return 0
    return ((out_exp & 0xFF) << 23) | lut[idx]


def rel_error(approx_bits: int, golden: float) -> float:
    approx = bits_to_f32(approx_bits)
    if not math.isfinite(golden) or golden == 0.0:
        return 0.0
    return abs((approx - golden) / golden)


def sweep_rcp(lut: List[int], lut_bits: int, samples: int, seed: int) -> Tuple[float, int]:
    rng = random.Random(seed)
    worst = 0.0
    worst_bits = 0
    probes = [0x3F800000, 0x40000000, 0x3F000000, 0xBF800000, 0x00800000, 0x7F7FFFFF]
    for exp in range(1, 255):
        for idx in range(0, 1 << lut_bits):
            frac = idx << (23 - lut_bits)
            probes.append((exp << 23) | frac)
    for _ in range(samples):
        probes.append(rng.getrandbits(32))
    for bits in probes:
        exp = (bits >> 23) & 0xFF
        frac = bits & 0x7FFFFF
        if exp == 0xFF or (exp == 0 and frac == 0):
            continue
        x = bits_to_f32(bits)
        if not math.isfinite(x) or x == 0.0:
            continue
        golden = f32(1.0 / x)
        if not math.isfinite(golden) or golden == 0.0:
            continue
        err = rel_error(model_rcp_bits(bits, lut, lut_bits), golden)
        if err > worst:
            worst = err
            worst_bits = bits
    return worst, worst_bits


def sweep_exp2(lut: List[int], lut_bits: int, samples: int, seed: int) -> Tuple[float, int]:
    rng = random.Random(seed)
    worst = 0.0
    worst_bits = 0
    probes = [f32_to_bits(x / 16.0) for x in range(-2016, 2033)]
    for _ in range(samples):
        x = rng.uniform(-126.0, 126.0)
        probes.append(f32_to_bits(x))
    for bits in probes:
        x = bits_to_f32(bits)
        golden = f32(2.0 ** x)
        if not math.isfinite(golden) or golden == 0.0:
            continue
        err = rel_error(model_exp2_bits(bits, lut, lut_bits), golden)
        if err > worst:
            worst = err
            worst_bits = bits
    return worst, worst_bits


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--lut-bits", type=int, default=12)
    ap.add_argument("--samples", type=int, default=200000)
    ap.add_argument("--seed", type=int, default=8008)
    ap.add_argument("--rcp-mem", type=Path, default=DEFAULT_RCP_MEM)
    ap.add_argument("--exp2-mem", type=Path, default=DEFAULT_EXP2_MEM)
    args = ap.parse_args()

    if args.lut_bits < 8 or args.lut_bits > 14:
        raise SystemExit("lut-bits must be in 8..14 for this FPGA-friendly SFU model")

    rcp_lut = build_rcp_lut(args.lut_bits)
    exp2_lut = build_exp2_lut(args.lut_bits)
    write_mem(args.rcp_mem, rcp_lut)
    write_mem(args.exp2_mem, exp2_lut)

    rcp_err, rcp_bits = sweep_rcp(rcp_lut, args.lut_bits, args.samples, args.seed)
    exp2_err, exp2_bits = sweep_exp2(exp2_lut, args.lut_bits, args.samples, args.seed + 1)

    print(f"SFU_SWEEP lut_bits={args.lut_bits} samples={args.samples}")
    print(f"RCP  max_rel_error={rcp_err:.8e} limit={RCP_REL_LIMIT:.8e} input=0x{rcp_bits:08x}")
    print(f"EXP2 max_rel_error={exp2_err:.8e} limit={EXP2_REL_LIMIT:.8e} input=0x{exp2_bits:08x}")

    if rcp_err > RCP_REL_LIMIT:
        raise SystemExit("SFU_SWEEP FAIL RCP relative error threshold")
    if exp2_err > EXP2_REL_LIMIT:
        raise SystemExit("SFU_SWEEP FAIL EXP2 relative error threshold")
    print("SFU_SWEEP PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
