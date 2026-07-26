#!/usr/bin/env python3
"""Bit-level AEC-G FP8 E4M3FN and MMA.m16n16k16.e4m3.f32 model."""

import argparse
import json
import math
import random
import struct
from fractions import Fraction
from pathlib import Path


CANONICAL_NAN_F32_BITS = 0x7FC00000
CANONICAL_NAN_FP8 = 0x7F
FP8_MAX_POS = 0x7E
FP8_MAX_NEG = 0xFE


def bits_to_f32(bits):
    return struct.unpack("<f", struct.pack("<I", bits & 0xFFFFFFFF))[0]


def f32_to_bits(value):
    try:
        return struct.unpack("<I", struct.pack("<f", float(value)))[0]
    except OverflowError:
        return 0xFF800000 if math.copysign(1.0, value) < 0.0 else 0x7F800000


def is_nan_bits(bits):
    return ((bits >> 23) & 0xFF) == 0xFF and (bits & 0x7FFFFF) != 0


def is_inf_bits(bits):
    return ((bits >> 23) & 0xFF) == 0xFF and (bits & 0x7FFFFF) == 0


def round_even_fraction(frac):
    q, r = divmod(frac.numerator, frac.denominator)
    cmp = r * 2 - frac.denominator
    if cmp > 0:
        return q + 1
    if cmp < 0:
        return q
    return q if (q & 1) == 0 else q + 1


def pow2_fraction(exp):
    return Fraction(1 << exp, 1) if exp >= 0 else Fraction(1, 1 << (-exp))


def floor_log2_fraction(frac):
    nbits = frac.numerator.bit_length()
    dbits = frac.denominator.bit_length()
    exp = nbits - dbits
    if frac < pow2_fraction(exp):
        exp -= 1
    return exp


def fraction_to_f32_bits(value):
    if value == 0:
        return 0
    sign = 0
    if value < 0:
        sign = 0x80000000
        value = -value

    exp = floor_log2_fraction(value)
    if exp > 127:
        return sign | 0x7F800000

    if exp >= -126:
        scaled = value * pow2_fraction(23 - exp)
        sig = round_even_fraction(scaled)
        if sig == (1 << 24):
            sig >>= 1
            exp += 1
        if exp > 127:
            return sign | 0x7F800000
        return sign | ((exp + 127) << 23) | ((sig - (1 << 23)) & 0x7FFFFF)

    sig = round_even_fraction(value * Fraction(1 << 149, 1))
    if sig == 0:
        return sign
    if sig >= (1 << 23):
        return sign | (1 << 23) | ((sig - (1 << 23)) & 0x7FFFFF)
    return sign | sig


def f32_bits_to_fraction(bits):
    bits &= 0xFFFFFFFF
    if is_nan_bits(bits):
        return None
    sign = -1 if (bits >> 31) else 1
    exp = (bits >> 23) & 0xFF
    frac = bits & 0x7FFFFF
    if exp == 0xFF:
        return math.inf if sign > 0 else -math.inf
    if exp == 0:
        if frac == 0:
            return Fraction(0, 1)
        return Fraction(sign * frac, 1) * Fraction(1, 1 << 149)
    return Fraction(sign * ((1 << 23) | frac), 1) * Fraction(1, 1 << 23) * pow2_fraction(exp - 127)


def fp8_e4m3fn_to_fraction(byte):
    b = byte & 0xFF
    exp = (b >> 3) & 0xF
    frac = b & 0x7
    if exp == 0xF and frac == 0x7:
        return None
    sign = -1 if (b & 0x80) else 1
    if exp == 0:
        return Fraction(sign * frac, 8) * Fraction(1, 64)
    if exp == 0xF:
        return Fraction(sign * (8 + frac), 8) * Fraction(1 << 8, 1)
    return Fraction(sign * (8 + frac), 8) * pow2_fraction(exp - 7)


def fp8_e4m3fn_to_f32_bits(byte):
    value = fp8_e4m3fn_to_fraction(byte)
    if value is None:
        return CANONICAL_NAN_F32_BITS
    return fraction_to_f32_bits(value)


def fma_f32_bits(a_bits, b_bits, c_bits):
    if is_nan_bits(a_bits) or is_nan_bits(b_bits) or is_nan_bits(c_bits):
        return CANONICAL_NAN_F32_BITS
    a = f32_bits_to_fraction(a_bits)
    b = f32_bits_to_fraction(b_bits)
    c = f32_bits_to_fraction(c_bits)
    if a in (math.inf, -math.inf) or b in (math.inf, -math.inf) or c in (math.inf, -math.inf):
        return f32_to_bits(bits_to_f32(a_bits) * bits_to_f32(b_bits) + bits_to_f32(c_bits))
    return fraction_to_f32_bits(a * b + c)


def pack_v4_fp8(bytes4):
    if len(bytes4) != 4:
        raise ValueError("expected four FP8 bytes")
    value = 0
    for idx, byte in enumerate(bytes4):
        value |= (byte & 0xFF) << (idx * 8)
    return value


def unpack_v4_fp8(word):
    return [(word >> (idx * 8)) & 0xFF for idx in range(4)]


def pack_fragments(a, b, c):
    frag = {}
    for lane in range(32):
        row = lane >> 1
        half = lane & 1
        col_base = 8 * half
        k_base = 8 * half
        b_col = lane >> 1
        frag[lane] = {
            "A": [
                pack_v4_fp8(a[row][col_base:col_base + 4]),
                pack_v4_fp8(a[row][col_base + 4:col_base + 8]),
            ],
            "B": [
                pack_v4_fp8([b[k_base + i][b_col] for i in range(4)]),
                pack_v4_fp8([b[k_base + 4 + i][b_col] for i in range(4)]),
            ],
            "C": [c[row][col_base + i] & 0xFFFFFFFF for i in range(8)],
        }
    return frag


def unpack_fragments(frag):
    a = [[0 for _ in range(16)] for _ in range(16)]
    b = [[0 for _ in range(16)] for _ in range(16)]
    c = [[0 for _ in range(16)] for _ in range(16)]
    for lane in range(32):
        row = lane >> 1
        half = lane & 1
        col_base = 8 * half
        k_base = 8 * half
        b_col = lane >> 1
        a0 = unpack_v4_fp8(frag[lane]["A"][0])
        a1 = unpack_v4_fp8(frag[lane]["A"][1])
        for i in range(4):
            a[row][col_base + i] = a0[i]
            a[row][col_base + 4 + i] = a1[i]
        b0 = unpack_v4_fp8(frag[lane]["B"][0])
        b1 = unpack_v4_fp8(frag[lane]["B"][1])
        for i in range(4):
            b[k_base + i][b_col] = b0[i]
            b[k_base + 4 + i][b_col] = b1[i]
        for i in range(8):
            c[row][col_base + i] = frag[lane]["C"][i] & 0xFFFFFFFF
    return a, b, c


def mma_m16n16k16_e4m3_f32_bits(a, b, c):
    out = [[0 for _ in range(16)] for _ in range(16)]
    for row in range(16):
        for col in range(16):
            acc = c[row][col] & 0xFFFFFFFF
            for k in range(16):
                aval = fp8_e4m3fn_to_f32_bits(a[row][k])
                bval = fp8_e4m3fn_to_f32_bits(b[k][col])
                acc = fma_f32_bits(aval, bval, acc)
            out[row][col] = acc
    return out


def fragment_results_from_matrix(d):
    out = {}
    for lane in range(32):
        row = lane >> 1
        half = lane & 1
        col_base = 8 * half
        out[lane] = [d[row][col_base + i] & 0xFFFFFFFF for i in range(8)]
    return out


def make_vectors(seed=9):
    rng = random.Random(seed)
    fp8_pool = [0x00, 0x80, 0x01, 0x81, 0x08, 0x38, 0x3C, 0x40, 0x7E, 0xFE, 0x7F]
    a = [[rng.choice(fp8_pool) for _ in range(16)] for _ in range(16)]
    b = [[rng.choice(fp8_pool) for _ in range(16)] for _ in range(16)]
    c = [[f32_to_bits(rng.uniform(-2.0, 2.0)) for _ in range(16)] for _ in range(16)]
    d = mma_m16n16k16_e4m3_f32_bits(a, b, c)
    return {"A": a, "B": b, "C": c, "fragments": pack_fragments(a, b, c), "D": d, "D_fragments": fragment_results_from_matrix(d)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--output", type=Path, default=Path("tests/mma_vectors.json"))
    ap.add_argument("--seed", type=int, default=9)
    args = ap.parse_args()
    data = make_vectors(args.seed)
    args.output.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="ascii")
    print("MMA_MODEL PASS wrote {}".format(args.output))


if __name__ == "__main__":
    main()
