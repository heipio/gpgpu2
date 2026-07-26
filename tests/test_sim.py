import math
import struct

from simulator import (
    CANONICAL_NAN_F32_BITS,
    FP8_E4M3FN_CANONICAL_NAN,
    FP8_E4M3FN_MAX_NEG,
    FP8_E4M3FN_MAX_POS,
    AECGSimulator,
    bits_to_f32,
    f32,
    f32_bits,
    float_to_fp8_e4m3fn,
    fp8_e4m3fn_to_float,
    mma_m16n16k16_e4m3_f32,
    pack_fp8,
    rel_error,
    sfu_exp2_f32,
    sfu_rcp_f32,
)


def test_fp8_known_values_and_specials():
    assert float_to_fp8_e4m3fn(0.0) == 0x00
    assert float_to_fp8_e4m3fn(-0.0) == 0x80
    assert float_to_fp8_e4m3fn(1.0) == 0x38
    assert float_to_fp8_e4m3fn(-1.0) == 0xB8
    assert float_to_fp8_e4m3fn(0.001953125) == 0x01
    assert float_to_fp8_e4m3fn(448.0) == FP8_E4M3FN_MAX_POS
    assert float_to_fp8_e4m3fn(1.0e30) == FP8_E4M3FN_MAX_POS
    assert float_to_fp8_e4m3fn(-1.0e30) == FP8_E4M3FN_MAX_NEG
    assert float_to_fp8_e4m3fn(math.inf) == FP8_E4M3FN_MAX_POS
    assert float_to_fp8_e4m3fn(-math.inf) == FP8_E4M3FN_MAX_NEG
    assert float_to_fp8_e4m3fn(math.nan) == FP8_E4M3FN_CANONICAL_NAN
    assert math.isnan(fp8_e4m3fn_to_float(0x7F))
    assert f32_bits(fp8_e4m3fn_to_float(0x00)) == 0x00000000
    assert f32_bits(fp8_e4m3fn_to_float(0x80)) == 0x80000000
    assert fp8_e4m3fn_to_float(0x7E) == 448.0
    assert fp8_e4m3fn_to_float(0xFE) == -448.0


def test_fp8_round_to_nearest_even_ties():
    # Midpoint between 1.0 (0x38, even fraction 0) and 1.125 (0x39).
    assert float_to_fp8_e4m3fn(1.0625) == 0x38
    # Midpoint between 1.125 (odd fraction 1) and 1.25 (even fraction 2).
    assert float_to_fp8_e4m3fn(1.1875) == 0x3A
    # Midpoint between subnormal 0x01 and 0x02 rounds to even 0x02.
    assert float_to_fp8_e4m3fn(0.0029296875) == 0x02


def test_sfu_rcp_precision_and_specials():
    samples = [-448.0, -17.5, -3.0, -1.0, -0.25, 0.25, 0.75, 1.0, 3.0, 17.5, 448.0]
    for x in samples:
        got = sfu_rcp_f32(x)
        ref = f32(1.0 / f32(x))
        assert rel_error(got, ref) <= 2.0 ** -10
    assert math.isinf(sfu_rcp_f32(0.0)) and sfu_rcp_f32(0.0) > 0
    neg_zero_rcp = sfu_rcp_f32(-0.0)
    assert math.isinf(neg_zero_rcp) and neg_zero_rcp < 0
    assert f32_bits(sfu_rcp_f32(math.inf)) == 0x00000000
    assert f32_bits(sfu_rcp_f32(-math.inf)) == 0x80000000
    assert f32_bits(sfu_rcp_f32(math.nan)) == CANONICAL_NAN_F32_BITS


def test_sfu_exp2_precision_and_specials():
    samples = [-20.0, -10.5, -1.0, 0.0, 0.5, 1.0, 7.25, 16.0]
    for x in samples:
        got = sfu_exp2_f32(x)
        ref = f32(2.0 ** f32(x))
        assert rel_error(got, ref) <= 2.0 ** -9
    assert sfu_exp2_f32(-200.0) == 0.0
    assert math.isinf(sfu_exp2_f32(200.0))
    assert math.isinf(sfu_exp2_f32(math.inf))
    assert sfu_exp2_f32(-math.inf) == 0.0
    assert f32_bits(sfu_exp2_f32(math.nan)) == CANONICAL_NAN_F32_BITS


def test_mma_accumulates_in_k_order():
    a = [[float_to_fp8_e4m3fn(0.0) for _ in range(16)] for _ in range(16)]
    b = [[float_to_fp8_e4m3fn(0.0) for _ in range(16)] for _ in range(16)]
    # This sequence exposes reassociation: (((1e8 + 1) - 1e8) + rest) differs
    # from tree-like or magnitude-sorted accumulation.
    vals = [448.0, 1.0, -448.0] + [1.0] * 13
    for k, v in enumerate(vals):
        a[0][k] = float_to_fp8_e4m3fn(v)
        b[k][0] = float_to_fp8_e4m3fn(1.0)
    out = mma_m16n16k16_e4m3_f32(a, b)
    acc = f32(0.0)
    for v in vals:
        acc = f32(acc + f32(fp8_e4m3fn_to_float(float_to_fp8_e4m3fn(v)) * 1.0))
    assert out[0][0] == acc
    assert out[0][0] == 14.0


def test_inactive_lanes_are_silent_for_sfu_writeback():
    sim = AECGSimulator()
    sim.active_mask = 0x0000FFFF
    for lane in range(32):
        sim.gpr[lane][1] = f32_bits(2.0)
        sim.gpr[lane][2] = 0xDEADBEEF
    sim.sfu_rcp(dst=2, src=1)
    for lane in range(16):
        assert bits_to_f32(sim.gpr[lane][2]) == 0.5
    for lane in range(16, 32):
        assert sim.gpr[lane][2] == 0xDEADBEEF

if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
    print("AEC-G simulator numeric tests passed")

