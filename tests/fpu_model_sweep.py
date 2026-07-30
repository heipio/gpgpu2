#!/usr/bin/env python3
"""AEC-G f32 FPU contract sweep.

This script is intentionally independent of vendor IP. It checks the golden
software rules that RTL must match: canonical NaN, signed-zero multiply, FMA
single rounding, and MAD double rounding.
"""

import random
import struct
import sys
from fractions import Fraction
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from mma_model import (  # noqa: E402
    CANONICAL_NAN_F32_BITS,
    f32_bits_to_fraction,
    fraction_to_f32_bits,
    is_inf_bits,
    is_nan_bits,
)


def bits_to_f32(bits: int) -> float:
    return struct.unpack("<f", struct.pack("<I", bits & 0xFFFFFFFF))[0]


def f32_to_bits(value: float) -> int:
    return struct.unpack("<I", struct.pack("<f", float(value)))[0]


def is_zero_bits(bits: int) -> bool:
    return (bits & 0x7FFFFFFF) == 0


def mul_f32_bits(a: int, b: int) -> int:
    if is_nan_bits(a) or is_nan_bits(b):
        return CANONICAL_NAN_F32_BITS
    if (is_inf_bits(a) and is_zero_bits(b)) or (is_zero_bits(a) and is_inf_bits(b)):
        return CANONICAL_NAN_F32_BITS
    if is_zero_bits(a) or is_zero_bits(b):
        return ((a ^ b) & 0x80000000)
    if is_inf_bits(a) or is_inf_bits(b):
        return ((a ^ b) & 0x80000000) | 0x7F800000
    return fraction_to_f32_bits(f32_bits_to_fraction(a) * f32_bits_to_fraction(b))


def add_f32_bits(a: int, b: int) -> int:
    if is_nan_bits(a) or is_nan_bits(b):
        return CANONICAL_NAN_F32_BITS
    if is_inf_bits(a) and is_inf_bits(b) and ((a ^ b) & 0x80000000):
        return CANONICAL_NAN_F32_BITS
    if is_inf_bits(a):
        return a
    if is_inf_bits(b):
        return b
    return fraction_to_f32_bits(f32_bits_to_fraction(a) + f32_bits_to_fraction(b))


def fma_f32_bits(a: int, b: int, c: int) -> int:
    if is_nan_bits(a) or is_nan_bits(b) or is_nan_bits(c):
        return CANONICAL_NAN_F32_BITS
    if (is_inf_bits(a) and is_zero_bits(b)) or (is_zero_bits(a) and is_inf_bits(b)):
        return CANONICAL_NAN_F32_BITS
    if is_inf_bits(a) or is_inf_bits(b):
        prod = ((a ^ b) & 0x80000000) | 0x7F800000
        return add_f32_bits(prod, c)
    if is_inf_bits(c):
        return c
    return fraction_to_f32_bits(
        f32_bits_to_fraction(a) * f32_bits_to_fraction(b) + f32_bits_to_fraction(c)
    )


def mad_f32_bits(a: int, b: int, c: int) -> int:
    return add_f32_bits(mul_f32_bits(a, b), c)


def finite_random_bits(rng: random.Random) -> int:
    while True:
      bits = rng.getrandbits(32)
      if not is_nan_bits(bits) and not is_inf_bits(bits):
          return bits


def main() -> int:
    edge_cases = [
        ("mul_neg_zero", mul_f32_bits(0xBF800000, 0x00000000), 0x80000000),
        ("mul_pos_zero", mul_f32_bits(0x80000000, 0xC0000000), 0x00000000),
        ("mul_inf_zero_nan", mul_f32_bits(0x7F800000, 0x00000000), CANONICAL_NAN_F32_BITS),
        ("add_inf_cancel_nan", add_f32_bits(0x7F800000, 0xFF800000), CANONICAL_NAN_F32_BITS),
        ("fma_inf_zero_nan", fma_f32_bits(0x7F800000, 0x00000000, 0x3F800000), CANONICAL_NAN_F32_BITS),
    ]
    for name, got, expected in edge_cases:
        if got != expected:
            raise SystemExit(f"{name}: got 0x{got:08x}, expected 0x{expected:08x}")

    rng = random.Random(0xAECF004)
    diff = None
    for _ in range(200000):
        a = finite_random_bits(rng)
        b = finite_random_bits(rng)
        c = finite_random_bits(rng)
        fma = fma_f32_bits(a, b, c)
        mad = mad_f32_bits(a, b, c)
        if fma != mad:
            diff = (a, b, c, fma, mad)
            break

    if diff is None:
        raise SystemExit("no MAD/FMA double-rounding witness found")

    a, b, c, fma, mad = diff
    print("FPU_MODEL_SWEEP PASS")
    print(f"MAD_FMA_WITNESS a=0x{a:08x} b=0x{b:08x} c=0x{c:08x} fma=0x{fma:08x} mad=0x{mad:08x}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
