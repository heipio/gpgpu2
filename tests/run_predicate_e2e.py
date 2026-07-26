#!/usr/bin/env python3
"""Stage 7.4 predicate execution end-to-end RTL test."""

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


def build_xsim_command():
    if os.name == "nt":
        raise RuntimeError("XSim automation is expected to run in the Vivado Linux environment")
    return [
        "bash",
        "-lc",
        "set -e; "
        "rm -rf xsim.dir *.jou *.log *.pb webtalk* tb_system_sim.wdb; "
        "xvlog -sv -L xpm {} >/tmp/aec_stage74_xvlog.out 2>&1; ".format(" ".join(RTL_SOURCES))
        + "xelab -L xpm tb_system -s tb_system_sim >/tmp/aec_stage74_xelab.out 2>&1; "
        + "xsim tb_system_sim -runall >/tmp/aec_stage74_xsim.out 2>&1; "
        + "cat /tmp/aec_stage74_xsim.out",
    ]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=74)
    ap.add_argument("--skip-xsim", action="store_true")
    args = ap.parse_args()

    rtl_dir = ROOT / "rtl"
    asm_path = ROOT / "tests" / "predicate_test.asm"
    aecbin_path = ROOT / "tests" / "predicate_test.aecbin"

    run(
        [
            sys.executable,
            str(ROOT / "compiler" / "aec_assembler.py"),
            str(asm_path),
            "-o",
            str(aecbin_path),
            "--format",
            "aecbin",
        ],
        ROOT,
    )

    rng = random.Random(args.seed)
    words = 8
    a = [rng.randrange(0, 2**31) for _ in range(words)]
    b = [rng.randrange(0, 2**31) for _ in range(words)]
    sentinel = [(0xDEAD0000 + i) & 0xFFFFFFFF for i in range(words)]
    out = [0] * words
    expected = [((a[i] + b[i]) & 0xFFFFFFFF) if i < 4 else sentinel[i] for i in range(words)]

    runtime = AECSimulatorRuntime(rtl_dir / "host_cmds.txt")
    dev_a = runtime.aecMalloc(words * 4)
    dev_b = runtime.aecMalloc(words * 4)
    dev_out = runtime.aecMalloc(words * 4)
    runtime.aecMemcpyH2D(dev_a, a)
    runtime.aecMemcpyH2D(dev_b, b)
    runtime.aecMemcpyH2D(dev_out, sentinel)
    runtime.aecModuleLoad(aecbin_path)
    runtime.aecKernelLaunch(0, 0x4000, [dev_a, dev_b, dev_out])
    runtime.aecSynchronize()
    runtime.aecMemcpyD2H(out, dev_out, words * 4)
    runtime.flush()

    if args.skip_xsim:
        print("PREDICATE_E2E COMMANDS generated at {}".format(rtl_dir / "host_cmds.txt"))
        return 0

    if shutil.which("xvlog") is None or shutil.which("xelab") is None or shutil.which("xsim") is None:
        raise SystemExit("Vivado XSim tools not found in PATH")

    run(build_xsim_command(), rtl_dir)
    runtime.load_pending_dumps()

    if out != expected:
        raise SystemExit("PREDICATE_E2E FAIL out={} expected={}".format(out, expected))
    print("PREDICATE_E2E PASS out={}".format([hex(x) for x in out]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
