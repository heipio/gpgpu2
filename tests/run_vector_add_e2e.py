#!/usr/bin/env python3
"""End-to-end Python runtime -> host_cmds -> XSim vector-add test."""

import argparse
import os
import random
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "runtime"))

from aec_runtime_sim import AECSimulatorRuntime


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


def build_xsim_command(rtl_dir: Path):
    shell = os.environ.get("SHELL", "")
    if os.name == "nt":
        raise RuntimeError("XSim automation is expected to run in the Vivado Linux environment")
    return [
        "bash",
        "-lc",
        "set -e; "
        "rm -rf xsim.dir *.jou *.log *.pb webtalk* tb_system_sim.wdb; "
        f"xvlog -sv -L xpm {' '.join(RTL_SOURCES)} >/tmp/aec_stage72_xvlog.out 2>&1; "
        "xelab -L xpm tb_system -s tb_system_sim >/tmp/aec_stage72_xelab.out 2>&1; "
        "xsim tb_system_sim -runall >/tmp/aec_stage72_xsim.out 2>&1; "
        "cat /tmp/aec_stage72_xsim.out",
    ]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--words", type=int, default=1, help="current RTL kernel supports 1 word")
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--skip-xsim", action="store_true")
    args = ap.parse_args()

    if args.words != 1:
        raise SystemExit("current Stage 7.2 RTL vector_add.asm supports exactly one 32-bit word")

    rtl_dir = ROOT / "rtl"
    asm_path = ROOT / "tests" / "vector_add.asm"
    aecbin_path = ROOT / "tests" / "vector_add.aecbin"

    run([sys.executable, str(ROOT / "compiler" / "aec_assembler.py"), str(asm_path), "-o", str(aecbin_path), "--format", "aecbin"], ROOT)

    rng = random.Random(args.seed)
    a = [rng.randrange(0, 2**31)]
    b = [rng.randrange(0, 2**31)]
    out = [0] * args.words
    expected = [(a[0] + b[0]) & 0xFFFFFFFF]

    runtime = AECSimulatorRuntime(rtl_dir / "host_cmds.txt")
    dev_a = runtime.aecMalloc(args.words * 4)
    dev_b = runtime.aecMalloc(args.words * 4)
    dev_out = runtime.aecMalloc(args.words * 4)
    runtime.aecMemcpyH2D(dev_a, a)
    runtime.aecMemcpyH2D(dev_b, b)
    runtime.aecModuleLoad(aecbin_path)
    runtime.aecKernelLaunch(0, 0x4000, [dev_a, dev_b, dev_out])
    runtime.aecSynchronize()
    runtime.aecMemcpyD2H(out, dev_out, args.words * 4)
    runtime.flush()

    if not args.skip_xsim:
        if shutil.which("xvlog") is None or shutil.which("xelab") is None or shutil.which("xsim") is None:
            raise SystemExit("Vivado XSim tools not found in PATH")
        run(build_xsim_command(rtl_dir), rtl_dir)
        runtime.load_pending_dumps()

    if args.skip_xsim:
        print(f"VECTOR_ADD_E2E COMMANDS generated at {rtl_dir / 'host_cmds.txt'}")
        return 0

    if out != expected:
        raise SystemExit(f"VECTOR_ADD_E2E FAIL out={out} expected={expected}")
    print(f"VECTOR_ADD_E2E PASS a={a[0]} b={b[0]} out={out[0]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
