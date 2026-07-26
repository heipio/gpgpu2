import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "compiler"))
sys.path.insert(0, os.path.join(ROOT, "tests"))

import aec_assembler  # noqa: E402
import compiler  # noqa: E402
import simulator  # noqa: E402


EXPECTED_CORE_OPCODES = {
    "NOP": 0x0000,
    "MOV": 0x0001,
    "IADD.u32": 0x0002,
    "IMUL.u32": 0x0003,
    "FADD.f32": 0x0004,
    "FMUL.f32": 0x0005,
    "MAD.f32": 0x0006,
    "FMA.f32": 0x0007,
    "SETP": 0x0008,
    "CMPP": 0x0009,
    "SUB.u32": 0x000A,
    "AND.b32": 0x000B,
    "OR.b32": 0x000C,
    "XOR.b32": 0x000D,
    "SHL.b32": 0x000E,
    "SHR.b32": 0x000F,
    "LD": 0x0010,
    "ST": 0x0011,
    "FENCE": 0x0012,
    "BRA": 0x0020,
    "BRX": 0x0021,
    "SSY": 0x0022,
    "SYNC": 0x0023,
    "BAR.SYNC": 0x0024,
    "HALT": 0x007F,
}

EXPECTED_SPECIALS = {
    "%laneid": 0x0100,
    "%warpid": 0x0101,
    "%ctaid.x": 0x0102,
    "%nctaid.x": 0x0103,
    "%activemask": 0x0104,
}

EXPECTED_SPACE = {
    "global": 0,
    "gmem": 0,
    "param": 1,
    "pmem": 1,
    "shared": 2,
    "smem": 2,
    "local": 3,
    "lmem": 3,
    "const": 4,
    "cmem": 4,
}


def _rtl_opcode_map():
    text = open(os.path.join(ROOT, "rtl", "aec_pkg.sv"), "r").read()
    return {
        name: int(value, 16)
        for name, value in re.findall(r"(AEC_OP_[A-Z0-9_]+)\s*=\s*16'h([0-9a-fA-F]+)", text)
    }


def _rtl_special_laneid():
    text = open(os.path.join(ROOT, "rtl", "ex_stage.sv"), "r").read()
    match = re.search(r"AEC_SR_LANEID\s*=\s*16'h([0-9a-fA-F]+)", text)
    assert match, "AEC_SR_LANEID localparam missing"
    return int(match.group(1), 16)


def _json_opcode_map():
    with open(os.path.join(ROOT, "aec_g_isa_v1.json"), "r") as fh:
        data = json.load(fh)
    return {item["mnemonic"]: int(item["opcode"], 16) for item in data["opcodes"]}


def _json_special_map():
    with open(os.path.join(ROOT, "aec_g_isa_v1.json"), "r") as fh:
        data = json.load(fh)
    names = {
        "SR_LANEID": "%laneid",
        "SR_WARPID": "%warpid",
        "SR_CTAID_X": "%ctaid.x",
        "SR_NCTAID_X": "%nctaid.x",
        "SR_ACTIVE_MASK": "%activemask",
    }
    return {
        names[item["name"]]: int(item["encoding"], 16)
        for item in data["register_file"]["special"]
        if "encoding" in item and item["name"] in names
    }


def test_opcode_contract_matches_json_assembler_compiler_simulator_and_rtl():
    rtl = _rtl_opcode_map()
    json_ops = _json_opcode_map()
    rtl_names = {
        "NOP": "AEC_OP_NOP",
        "MOV": "AEC_OP_MOV",
        "IADD.u32": "AEC_OP_IADD_U32",
        "IMUL.u32": "AEC_OP_IMUL_U32",
        "FADD.f32": "AEC_OP_FADD_F32",
        "FMUL.f32": "AEC_OP_FMUL_F32",
        "MAD.f32": "AEC_OP_MAD_F32",
        "FMA.f32": "AEC_OP_FMA_F32",
        "SETP": "AEC_OP_SETP",
        "CMPP": "AEC_OP_CMPP",
        "SUB.u32": "AEC_OP_SUB_U32",
        "AND.b32": "AEC_OP_AND_B32",
        "OR.b32": "AEC_OP_OR_B32",
        "XOR.b32": "AEC_OP_XOR_B32",
        "SHL.b32": "AEC_OP_SHL_B32",
        "SHR.b32": "AEC_OP_SHR_B32",
        "LD": "AEC_OP_LD",
        "ST": "AEC_OP_ST",
        "FENCE": "AEC_OP_FENCE",
        "BRA": "AEC_OP_BRA",
        "BRX": "AEC_OP_BRX",
        "SSY": "AEC_OP_SSY",
        "SYNC": "AEC_OP_SYNC",
        "BAR.SYNC": "AEC_OP_BAR_SYNC",
        "HALT": "AEC_OP_HALT",
    }
    assembler_names = {
        "MOV": "MOV",
        "IADD.u32": "ADD",
        "IMUL.u32": "MUL",
        "FADD.f32": "FADD",
        "FMUL.f32": "FMUL",
        "MAD.f32": "MAD",
        "FMA.f32": "FMA",
        "SUB.u32": "SUB",
        "AND.b32": "AND",
        "OR.b32": "OR",
        "XOR.b32": "XOR",
        "SHL.b32": "SHL",
        "SHR.b32": "SHR",
        "BRA": "BRA",
        "BAR.SYNC": "BAR",
    }
    for mnemonic, value in EXPECTED_CORE_OPCODES.items():
        assert json_ops[mnemonic] == value
        assert rtl[rtl_names[mnemonic]] == value
        assert simulator.AEC_OPCODE_BY_VALUE[value] == mnemonic
        if mnemonic in compiler.OPCODES:
            assert compiler.OPCODES[mnemonic] == value
        asm_key = assembler_names.get(mnemonic, mnemonic)
        if asm_key in aec_assembler.OPCODES:
            assert aec_assembler.OPCODES[asm_key] == value


def test_special_register_and_space_contracts_are_single_source_consistent():
    assert _rtl_special_laneid() == EXPECTED_SPECIALS["%laneid"]
    for name, value in EXPECTED_SPECIALS.items():
        assert aec_assembler.SPECIAL_REGS[name] == value
    json_specials = _json_special_map()
    assert json_specials["%laneid"] == EXPECTED_SPECIALS["%laneid"]
    assert json_specials["%activemask"] == EXPECTED_SPECIALS["%activemask"]
    for name, value in EXPECTED_SPACE.items():
        assert aec_assembler.SPACE_CODES[name] == value
        assert compiler.SPACE[name] == value


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
    print("contract audit tests passed")
