#!/usr/bin/env python3
"""End-to-end Stage 8 SFU RCP/EXP2 RTL test."""

import argparse
import math
import os
import shutil
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "runtime"))
sys.path.insert(0, str(ROOT / "tests"))

from aec_runtime_sim import AECSimulatorRuntime
from sfu_model_sweep import (
    CANONICAL_NAN,
    EXP2_REL_LIMIT,
    RCP_REL_LIMIT,
    bits_to_f32,
    f32,
    f32_to_bits,
)


RTL_SOURCES = [
    "aec_pkg.sv",
    "alu_lane.sv",
    "sfu.sv",
    "csr_regfile.sv",
    "fetch_decode.sv",
    "id_stage.sv",
    "issue_stage.sv",
    "vrf_lane.sv",
    "vrf_top.sv",
    "prf_top.sv",
    "simt_stack.sv",
    "ex_stage.sv",
    "lsu.sv",
    "wb_stage.sv",
    "trace_logger.sv",
    "imem.sv",
    "if_stage.sv",
    "cu_top.sv",
    "tb_system.sv",
]


def run(cmd, cwd):
    subprocess.run(cmd, cwd=cwd, check=True)


def build_xsim_command():
    if os.name == "nt":
        raise RuntimeError("XSim automation is expected to run in the Vivado Linux environment")
    return [
        "bash",
        "-lc",
        "set -e; "
        "rm -rf xsim.dir *.jou *.log *.pb webtalk* tb_system_sim.wdb; "
        "xvlog -sv -L xpm {} >/tmp/aec_stage8_xvlog.out 2>&1; ".format(" ".join(RTL_SOURCES))
        + "xelab -L xpm tb_system -s tb_system_sim >/tmp/aec_stage8_xelab.out 2>&1; "
        + "xsim tb_system_sim -runall >/tmp/aec_stage8_xsim.out 2>&1; "
        + "cat /tmp/aec_stage8_xsim.out",
    ]


def rel_error(actual_bits: int, expected: float) -> float:
    if math.isnan(expected) or math.isinf(expected) or expected == 0.0:
        return 0.0
    actual = bits_to_f32(actual_bits)
    return abs((actual - expected) / expected)


def assert_special_or_rel(name: str, actual_bits: int, expected_bits: int, limit: float) -> None:
    expected = bits_to_f32(expected_bits)
    actual = bits_to_f32(actual_bits)
    if math.isnan(expected):
        if actual_bits != CANONICAL_NAN:
            raise SystemExit(f"{name} FAIL expected canonical NaN got 0x{actual_bits:08x}")
        return
    if math.isinf(expected) or expected == 0.0:
        if actual_bits != expected_bits:
            raise SystemExit(f"{name} FAIL expected 0x{expected_bits:08x} got 0x{actual_bits:08x}")
        return
    err = rel_error(actual_bits, expected)
    if err > limit:
        raise SystemExit(
            f"{name} FAIL rel_error={err:.8e} limit={limit:.8e} actual={actual} expected={expected}"
        )


def golden_rcp_bits(bits: int) -> int:
    exp = (bits >> 23) & 0xFF
    frac = bits & 0x7FFFFF
    sign = bits & 0x80000000
    if exp == 0xFF and frac != 0:
        return CANONICAL_NAN
    if exp == 0 and frac == 0:
        return sign | 0x7F800000
    if exp == 0xFF:
        return sign
    y = f32(1.0 / bits_to_f32(bits))
    return f32_to_bits(y)


def golden_exp2_bits(bits: int) -> int:
    exp = (bits >> 23) & 0xFF
    frac = bits & 0x7FFFFF
    if exp == 0xFF and frac != 0:
        return CANONICAL_NAN
    if bits == 0x7F800000:
        return 0x7F800000
    if bits == 0xFF800000:
        return 0
    x = bits_to_f32(bits)
    y = 2.0 ** x
    if y > 3.4028234663852886e38:
        return 0x7F800000
    if y < 1.1754943508222875e-38:
        return 0
    return f32_to_bits(f32(y))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--skip-xsim", action="store_true")
    args = ap.parse_args()

    rtl_dir = ROOT / "rtl"
    asm_path = ROOT / "tests" / "sfu_test.asm"
    aecbin_path = ROOT / "tests" / "sfu_test.aecbin"

    run([sys.executable, str(ROOT / "tests" / "sfu_model_sweep.py"), "--samples", "50000"], ROOT)
    run([sys.executable, str(ROOT / "compiler" / "aec_assembler.py"), str(asm_path), "-o", str(aecbin_path), "--format", "aecbin"], ROOT)

    input_bits = [
        f32_to_bits(1.25),
        f32_to_bits(3.5),
        f32_to_bits(-4.0),
        f32_to_bits(0.75),
        0x00000000,
        0x80000000,
        0x7F800000,
        0x7FC12345,
    ]
    rcp_out = [0] * 8
    exp2_out = [0] * 8

    runtime = AECSimulatorRuntime(rtl_dir / "host_cmds.txt")
    dev_in = runtime.aecMalloc(32)
    dev_rcp = runtime.aecMalloc(32)
    dev_exp2 = runtime.aecMalloc(32)
    runtime.aecMemcpyH2D(dev_in, input_bits)
    runtime.aecModuleLoad(aecbin_path)
    runtime.aecKernelLaunch(0, 0x4000, [dev_in, dev_rcp, dev_exp2])
    runtime.aecSynchronize()
    runtime.aecMemcpyD2H(rcp_out, dev_rcp, 32)
    runtime.aecMemcpyD2H(exp2_out, dev_exp2, 32)
    runtime.flush()

    if args.skip_xsim:
        print(f"SFU_E2E COMMANDS generated at {rtl_dir / 'host_cmds.txt'}")
        return 0

    if shutil.which("xvlog") is None or shutil.which("xelab") is None or shutil.which("xsim") is None:
        raise SystemExit("Vivado XSim tools not found in PATH")

    run(build_xsim_command(), rtl_dir)
    runtime.load_pending_dumps()

    for idx, bits in enumerate(input_bits):
        assert_special_or_rel(f"RCP lane {idx}", rcp_out[idx], golden_rcp_bits(bits), RCP_REL_LIMIT)
        assert_special_or_rel(f"EXP2 lane {idx}", exp2_out[idx], golden_exp2_bits(bits), EXP2_REL_LIMIT)
    print("SFU_E2E PASS")
    print("RCP  out={}".format([f"0x{x:08x}" for x in rcp_out]))
    print("EXP2 out={}".format([f"0x{x:08x}" for x in exp2_out]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
