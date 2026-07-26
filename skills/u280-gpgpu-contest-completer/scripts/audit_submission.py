#!/usr/bin/env python3
"""Lightweight repository audit for the U280-GPGPU contest skill.

This script intentionally checks structure and obvious evidence only. It does
not prove correctness; it gives the agent and user a fast gap list before deeper
review.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Iterable


REQUIRED_DIRS = [
    "rtl",
    "constraints",
    "platform",
    "driver",
    "runtime",
    "compiler",
    "pytorch",
    "tests",
    "bitstream",
    "reports",
    "docs",
]

RUNTIME_APIS = [
    "aecContextCreate",
    "aecMalloc",
    "aecFree",
    "aecMemcpyH2D",
    "aecMemcpyD2H",
    "aecModuleLoad",
    "aecKernelLaunch",
    "aecSynchronize",
    "aecGetLastError",
    "aecReadCounters",
]

DESIGN_KEYS = [
    "logical_warp_width",
    "physical_simd_lanes",
    "issue_beats_per_warp",
    "cu",
    "cu_count",
    "cache",
    "cache_sizes",
    "gemm",
    "gemm_tiles",
    "frequency",
    "numeric_mode",
    "numeric_modes",
    "runtime_capability",
    "driver_version",
]

ENV_NEEDLES = [
    "CentOS",
    "GLIBC",
    "2022.2",
    "2.13.479",
    "U280 Gen3x16 XDMA base_1",
]


def iter_text_files(root: Path, subdirs: Iterable[str]) -> Iterable[Path]:
    suffixes = {
        ".h",
        ".hpp",
        ".c",
        ".cc",
        ".cpp",
        ".py",
        ".sv",
        ".v",
        ".vh",
        ".json",
        ".md",
        ".tcl",
        ".cmake",
        ".txt",
    }
    for subdir in subdirs:
        base = root / subdir
        if not base.exists():
            continue
        for path in base.rglob("*"):
            if path.is_file() and path.suffix.lower() in suffixes:
                yield path


def file_contains(path: Path, needle: str) -> bool:
    try:
        return needle in path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return False


def any_contains(root: Path, subdirs: Iterable[str], needle: str) -> bool:
    return any(file_contains(path, needle) for path in iter_text_files(root, subdirs))


def status(label: str, ok: bool, detail: str = "") -> str:
    mark = "OK" if ok else "MISSING"
    suffix = f" - {detail}" if detail else ""
    return f"[{mark}] {label}{suffix}"


def audit(root: Path) -> int:
    print(f"U280-GPGPU contest audit: {root}")
    print()

    missing_dirs = []
    for name in REQUIRED_DIRS:
        ok = (root / name).is_dir()
        if not ok:
            missing_dirs.append(name)
        print(status(f"directory {name}/", ok))

    print()
    design_path = root / "design.json"
    if design_path.exists():
        try:
            design = json.loads(design_path.read_text(encoding="utf-8"))
            print(status("design.json parses as JSON", True))
            for key in DESIGN_KEYS:
                print(status(f"design.json key {key}", key in design))
            lww = design.get("logical_warp_width")
            lanes = design.get("physical_simd_lanes")
            beats = design.get("issue_beats_per_warp")
            if isinstance(lww, int) and isinstance(lanes, int) and isinstance(beats, int) and lanes:
                ok = lww % lanes == 0 and lww // lanes == beats
                print(status("issue_beats_per_warp consistency", ok, f"{lww}/{lanes} -> {beats}"))
            else:
                print(status("issue_beats_per_warp consistency", False, "need integer logical_warp_width, physical_simd_lanes, issue_beats_per_warp"))
        except json.JSONDecodeError as exc:
            print(status("design.json parses as JSON", False, str(exc)))
    else:
        print(status("design.json", False))

    print()
    for api in RUNTIME_APIS:
        print(status(f"runtime API symbol {api}", any_contains(root, ["runtime", "driver", "pytorch", "tests"], api)))

    print()
    evidence_checks = [
        ("AEC-G mention", ["compiler", "rtl", "docs", "tests"], "AEC"),
        ("FP8/E4M3 mention", ["rtl", "compiler", "tests", "docs", "pytorch"], "e4m3"),
        ("optional E5M2 capability mention", ["rtl", "compiler", "tests", "docs", "pytorch"], "E5M2"),
        ("FP8 max finite 448 mention", ["rtl", "compiler", "tests", "docs", "pytorch"], "448"),
        ("round-to-nearest-even/RNE mention", ["rtl", "compiler", "tests", "docs"], "round-to-nearest-even"),
        ("canonical NaN mention", ["rtl", "compiler", "tests", "docs"], "canonical NaN"),
        ("subnormal handling mention", ["rtl", "compiler", "tests", "docs"], "subnormal"),
        ("MAD vs FMA rounding mention", ["rtl", "compiler", "tests", "docs"], "MAD"),
        ("inactive-lane write mask mention", ["rtl", "compiler", "tests", "docs"], "Inactive lanes"),
        ("MMA mention", ["rtl", "compiler", "tests", "docs"], "MMA"),
        ("MMA k-order mention", ["rtl", "compiler", "tests", "docs"], "k=0..15"),
        ("MMA C/D 8-alignment mention", ["rtl", "compiler", "tests", "docs"], "8-register"),
        ("REDUCE.ADD tree order mention", ["rtl", "compiler", "tests", "docs"], "REDUCE.ADD"),
        ("cross-beat SHFL/REDUCE mention", ["rtl", "compiler", "tests", "docs"], "Cross-beat"),
        ("64-bit even register pair mention", ["rtl", "compiler", "tests", "docs"], "even-aligned"),
        ("b128 lowering/rejection mention", ["rtl", "compiler", "tests", "docs"], ".b128"),
        ("aecbin fixed-width mention", ["compiler", "tests", "docs"], "four little-endian 32-bit words"),
        ("64-bit address window mention", ["runtime", "compiler", "rtl", "docs", "tests"], "address-window"),
        ("64-bit pointer truncation guard mention", ["runtime", "compiler", "rtl", "docs", "tests"], "truncate"),
        ("SFU mention", ["rtl", "compiler", "tests", "docs"], "SFU"),
        ("SFU RCP precision gate mention", ["rtl", "compiler", "tests", "docs"], "2^-10"),
        ("SFU EXP2 precision gate mention", ["rtl", "compiler", "tests", "docs"], "2^-9"),
        ("SFU special-value mapping mention", ["rtl", "compiler", "tests", "docs"], "+/-0"),
        ("SFU arbitration/back-pressure mention", ["rtl", "tests", "docs"], "arbitration"),
        ("SFU request tagging mention", ["rtl", "tests", "docs"], "tags"),
        ("SIMT mention", ["rtl", "tests", "docs"], "SIMT"),
        ("BRX divergence both-path mention", ["rtl", "tests", "docs"], "BRX"),
        ("SSY/SYNC reconvergence stack mention", ["rtl", "tests", "docs"], "SSY"),
        ("SIMT_STACK_FAULT mention", ["rtl", "tests", "docs"], "SIMT_STACK_FAULT"),
        ("dynamic BAR.SYNC expected_warps=0 mention", ["rtl", "tests", "docs"], "expected_warps=0"),
        ("FENCE subop=0 CTA mention", ["rtl", "runtime", "tests", "docs"], "subop=0"),
        ("FENCE subop=1 DEVICE mention", ["rtl", "runtime", "tests", "docs"], "subop=1"),
        ("capability unsupported feature mention", ["rtl", "runtime", "compiler", "docs", "tests"], "AEC_ERROR_UNSUPPORTED_FEATURE"),
        ("XDMA mention", ["platform", "driver", "runtime", "docs"], "XDMA"),
        ("HBM/DDR placement mention", ["runtime", "pytorch", "rtl", "docs", "reports"], "HBM/DDR"),
        ("DDR4 capacity tier mention", ["runtime", "pytorch", "rtl", "docs", "reports"], "DDR4"),
        ("per-SLR utilization mention", ["constraints", "platform", "rtl", "docs", "reports"], "per-SLR"),
        ("cross-SLR pipeline mention", ["constraints", "platform", "rtl", "docs", "reports"], "cross-SLR"),
        ("register slice mention", ["constraints", "platform", "rtl", "docs", "reports"], "register slice"),
        ("SFU LUT implementation mention", ["rtl", "compiler", "tests", "docs"], "lookup"),
        ("SFU interpolation/refinement mention", ["rtl", "compiler", "tests", "docs"], "interpolation"),
        ("fallback logging mention", ["pytorch", "runtime", "docs", "tests"], "fallback"),
        ("fallback reason mention", ["pytorch", "runtime", "docs", "tests"], "reason"),
        ("fallback CPU time mention", ["pytorch", "runtime", "docs", "tests"], "CPU time"),
        ("fallback I/O bytes mention", ["pytorch", "runtime", "docs", "tests"], "input/output bytes"),
        ("on-device LLM argmax mention", ["pytorch", "runtime", "docs", "tests"], "argmax on device"),
        ("LLM EOS padding mention", ["pytorch", "runtime", "docs", "tests"], "eos_token_id"),
        ("warm-up contamination mention", ["pytorch", "runtime", "docs", "tests"], "Warm-up"),
        ("state reset mention", ["pytorch", "runtime", "docs", "tests"], "state-reset"),
        ("KV cache clearing mention", ["pytorch", "runtime", "docs", "tests"], "KV cache"),
        ("misaligned access fault mention", ["rtl", "compiler", "runtime", "docs", "tests"], "MISALIGNED_ACCESS"),
        ("cache flush/invalidate mention", ["runtime", "rtl", "docs", "tests"], "flush/invalidate"),
        ("latency queue_depth=1 mention", ["pytorch", "runtime", "docs", "tests"], "queue_depth=1"),
        ("dynamic batching disabled mention", ["pytorch", "runtime", "docs", "tests"], "dynamic batching"),
        ("legal CPU layout transform mention", ["pytorch", "runtime", "docs", "tests"], "layout transformation"),
        ("WNS/timing evidence mention", ["reports", "docs"], "WNS"),
        ("zero timing violations mention", ["reports", "docs"], "WNS >= 0"),
        ("dynamic shared memory ABI mention", ["compiler", "runtime", "docs", "tests"], "dynamic_smem_bytes"),
        ("energy efficiency mention", ["reports", "docs", "rtl"], "tokens/J"),
        ("thermal/power reset mention", ["reports", "docs", "rtl"], "power-limit"),
        ("anti-hardcode unknown kernel mention", ["compiler", "docs", "tests"], "hardcoded"),
        ("open bonus manifest mention", ["reports", "docs", "tests"], "open_bonus_manifest"),
        ("open bonus baseline prerequisite mention", ["reports", "docs", "tests"], "baseline 25-point correctness"),
        ("one-click or staged build script mention", ["docs", "platform", "runtime", "compiler"], "build scripts"),
        ("xbutil board evidence mention", ["docs", "reports", "platform"], "xbutil examine"),
        ("U280 platform name mention", ["docs", "platform", "reports"], "xilinx_u280_gen3x16_xdma_1_202211_1"),
        ("connectivity.cfg mention", ["docs", "platform", "reports"], "connectivity.cfg"),
        ("explicit HBM port mapping mention", ["docs", "platform", "reports"], "HBM["),
        ("real board mode unset emulation mention", ["docs", "platform", "reports"], "unset XCL_EMULATION_MODE"),
        ("local/official tool mismatch mention", ["docs", "reports"], "version mismatch"),
        ("LLM 18-point priority mention", ["pytorch", "runtime", "docs", "reports"], "18 points"),
        ("ResNet-50 12-point priority mention", ["pytorch", "runtime", "docs", "reports"], "12 points"),
    ]
    for label, subdirs, needle in evidence_checks:
        print(status(label, any_contains(root, subdirs, needle)))

    print()
    for needle in ENV_NEEDLES:
        print(status(f"environment lock mention {needle}", any_contains(root, ["docs", "runtime", "compiler", "platform", "reports"], needle)))

    print()
    bitstream_dir = root / "bitstream"
    bitstreams = []
    if bitstream_dir.exists():
        for pattern in ("*.xclbin", "*.bit", "*.bin"):
            bitstreams.extend(bitstream_dir.rglob(pattern))
    print(status("bitstream/xclbin artifact", bool(bitstreams), ", ".join(str(p.relative_to(root)) for p in bitstreams[:5])))

    report_dir = root / "reports"
    reports = []
    if report_dir.exists():
        for pattern in ("*timing*", "*util*", "*power*", "*benchmark*", "*trace*"):
            reports.extend(report_dir.rglob(pattern))
    print(status("timing/util/power/benchmark reports", bool(reports), ", ".join(str(p.relative_to(root)) for p in reports[:8])))

    build_files = []
    for name in ("Makefile", "makefile", "CMakeLists.txt", "build.sh", "run_build.sh"):
        build_files.extend(root.rglob(name))
    print(status("one-click or staged build files", bool(build_files), ", ".join(str(p.relative_to(root)) for p in build_files[:8])))

    critical_missing = bool(missing_dirs) or not design_path.exists()
    return 1 if critical_missing else 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("repo", nargs="?", default=os.getcwd(), help="repository root to audit")
    args = parser.parse_args()
    return audit(Path(args.repo).resolve())


if __name__ == "__main__":
    raise SystemExit(main())
