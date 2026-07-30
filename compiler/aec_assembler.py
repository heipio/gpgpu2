#!/usr/bin/env python3
"""AEC-G v1.0 textual assembler.

The emitted instruction is the fixed 128-bit AEC-G word:

  [127:112] opcode
  [111:96]  pred_ctrl
  [95:80]   dst
  [79:64]   src1
  [63:32]   src2_or_imm32
  [31:0]    src3_or_immext

Hex output is one big-endian 128-bit text word per line, matching the existing
SystemVerilog testbench convention. Binary output is headerless .aecbin:
four little-endian 32-bit words per instruction, w0,w1,w2,w3.
"""

import argparse
import re
import struct
import sys
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple


INSTR_BYTES = 16
MAX_GPR = 255
MAX_PRED = 7


class AssemblerError(ValueError):
    pass


OPCODES: Dict[str, int] = {
    "ADD": 0x0001,
    "IADD": 0x0001,
    "FADD": 0x0001,
    "SUB": 0x0002,
    "MUL": 0x0003,
    "IMUL": 0x0003,
    "FMUL": 0x0003,
    "MAD": 0x0004,
    "FMA": 0x0005,
    "AND": 0x0010,
    "OR": 0x0011,
    "XOR": 0x0012,
    "NOT": 0x0013,
    "SHL": 0x0014,
    "SHR": 0x0015,
    "SAR": 0x0016,
    "SETP": 0x0020,
    "CMPP": 0x0021,
    "SEL": 0x0022,
    "LD": 0x0030,
    "ST": 0x0031,
    "FENCE": 0x0034,
    "BR": 0x0040,
    "BRA": 0x0040,
    "BRX": 0x0041,
    "SSY": 0x0042,
    "SYNC": 0x0043,
    "BAR": 0x0044,
    "HALT": 0x0045,
    "CPY": 0x0054,
    "MOV": 0x0054,
    "LOADI": 0x0055,
    "LOADI64": 0x0056,
    "CVT": 0x0057,
    "PACK": 0x0058,
    "UNPACK": 0x0059,
    "SHFL": 0x0060,
    "REDUCE": 0x0061,
    "MMA": 0x0070,
    "SFU": 0x0080,
    "RCP": 0x0080,
    "EXP2": 0x0080,
    "NOP": 0x00F0,
}

TYPE_CODES: Dict[str, int] = {
    "b8": 0x0,
    "u8": 0x0,
    "s8": 0x0,
    "b16": 0x1,
    "u16": 0x1,
    "s16": 0x1,
    "b32": 0x2,
    "u32": 0x2,
    "s32": 0x2,
    "b64": 0x3,
    "u64": 0x3,
    "s64": 0x3,
    "f16": 0x7,
    "f32": 0x8,
    "e4m3": 0xB,
    "v4e4m3": 0xD,
    "pred": 0xE,
}

SPACE_CODES: Dict[str, int] = {
    "gmem": 0x0,
    "global": 0x0,
    "pmem": 0x1,
    "param": 0x1,
    "smem": 0x2,
    "shared": 0x2,
    "lmem": 0x3,
    "local": 0x3,
    "cmem": 0x4,
    "const": 0x4,
}

CMP_CODES: Dict[str, int] = {
    "eq": 0,
    "ne": 1,
    "lt": 2,
    "le": 3,
    "gt": 4,
    "ge": 5,
}

SPECIAL_REGS: Dict[str, int] = {
    "%tid.x": 0x0100,
    "%laneid": 0x0100,
    "%warpid": 0x0101,
    "%ctaid.x": 0x0102,
    "%nctaid.x": 0x0103,
    "%activemask": 0x0104,
}

WIDTH_FROM_TYPE = {
    0x0: 8,
    0x1: 16,
    0x2: 32,
    0x3: 64,
    0x8: 32,
}


class PredCtrl:
    def __init__(
        self,
        pred: int = 0,
        pred_enable: bool = False,
        pred_negate: bool = False,
        type_code: int = TYPE_CODES["u32"],
        imm_en: bool = False,
        space_code: int = SPACE_CODES["gmem"],
        ctrl: int = 0,
    ) -> None:
        self.pred = pred
        self.pred_enable = pred_enable
        self.pred_negate = pred_negate
        self.type_code = type_code
        self.imm_en = imm_en
        self.space_code = space_code
        self.ctrl = ctrl

    def encode(self) -> int:
        value = 0
        value |= self.pred & 0x7
        value |= (self.type_code & 0xF) << 3
        value |= (1 if self.imm_en else 0) << 7
        value |= (self.ctrl & 0x7) << 8
        value |= (self.space_code & 0x7) << 11
        value |= (1 if self.pred_negate else 0) << 14
        value |= (1 if self.pred_enable else 0) << 15
        return value & 0xFFFF


class Instruction:
    def __init__(
        self,
        opcode: int,
        pred_ctrl: int = 0,
        dst: int = 0,
        src1: int = 0,
        src2: int = 0,
        src3: int = 0,
        line_no: int = 0,
        text: str = "",
    ) -> None:
        self.opcode = opcode
        self.pred_ctrl = pred_ctrl
        self.dst = dst
        self.src1 = src1
        self.src2 = src2
        self.src3 = src3
        self.line_no = line_no
        self.text = text

    def encode_int(self) -> int:
        return (
            ((self.opcode & 0xFFFF) << 112)
            | ((self.pred_ctrl & 0xFFFF) << 96)
            | ((self.dst & 0xFFFF) << 80)
            | ((self.src1 & 0xFFFF) << 64)
            | ((self.src2 & 0xFFFFFFFF) << 32)
            | (self.src3 & 0xFFFFFFFF)
        )

    def to_hex(self) -> str:
        return f"{self.encode_int():032x}"

    def to_aecbin(self) -> bytes:
        value = self.encode_int()
        return struct.pack(
            "<IIII",
            value & 0xFFFFFFFF,
            (value >> 32) & 0xFFFFFFFF,
            (value >> 64) & 0xFFFFFFFF,
            (value >> 96) & 0xFFFFFFFF,
        )


class ParsedLine:
    def __init__(
        self,
        mnemonic: str,
        suffixes: Tuple[str, ...],
        operands: List[str],
        pred: Optional[str],
        line_no: int,
        text: str,
    ) -> None:
        self.mnemonic = mnemonic
        self.suffixes = suffixes
        self.operands = operands
        self.pred = pred
        self.line_no = line_no
        self.text = text


class Assembler:
    def __init__(self) -> None:
        self.labels: Dict[str, int] = {}
        self.parsed: List[ParsedLine] = []

    def assemble_text(self, text: str) -> List[Instruction]:
        self.labels = {}
        self.parsed = []
        self._parse(text)
        return [self._encode(line) for line in self.parsed]

    def _parse(self, text: str) -> None:
        pc = 0
        for line_no, raw in enumerate(text.splitlines(), 1):
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            while True:
                match = re.match(r"^([A-Za-z_.$][\w.$]*):\s*(.*)$", line)
                if not match:
                    break
                label = match.group(1)
                if label in self.labels:
                    raise self._err(line_no, f"duplicate label {label}")
                self.labels[label] = pc
                line = match.group(2).strip()
                if not line:
                    break
            if not line:
                continue
            if line.endswith(";"):
                line = line[:-1].strip()

            pred = None
            if line.startswith("@"):
                pred_token, line = line.split(None, 1)
                pred = pred_token[1:]

            if " " in line:
                op, rest = line.split(None, 1)
                operands = self._split_operands(rest)
            else:
                op, operands = line, []

            parts = op.split(".")
            mnemonic = self._normalize_mnemonic(parts[0], line_no)
            suffixes = tuple(part.lower() for part in parts[1:] if part)
            self.parsed.append(ParsedLine(mnemonic, suffixes, operands, pred, line_no, raw.strip()))
            pc += 1

    def _encode(self, line: ParsedLine) -> Instruction:
        try:
            if line.mnemonic in ("NOP", "HALT", "SYNC"):
                self._expect(line, 0)
                return self._inst(line)
            if line.mnemonic in ("ADD", "SUB", "MUL", "AND", "OR", "XOR", "SHL", "SHR"):
                return self._encode_alu3(line)
            if line.mnemonic in ("CPY", "MOV"):
                return self._encode_cpy(line)
            if line.mnemonic == "LOADI":
                return self._encode_loadi(line)
            if line.mnemonic in ("SETP", "CMPP"):
                return self._encode_setp(line)
            if line.mnemonic in ("RCP", "EXP2"):
                return self._encode_sfu_unary(line)
            if line.mnemonic == "MMA":
                return self._encode_mma(line)
            if line.mnemonic == "LD":
                return self._encode_ld(line)
            if line.mnemonic == "ST":
                return self._encode_st(line)
            if line.mnemonic in ("BR", "BRA"):
                return self._encode_br(line)
            if line.mnemonic == "BRX":
                return self._encode_brx(line)
            if line.mnemonic in ("SSY",):
                return self._encode_target_only(line)
            if line.mnemonic == "BAR":
                return self._encode_bar(line)
            raise self._err(line.line_no, f"unsupported mnemonic {line.mnemonic}")
        except AssemblerError:
            raise
        except Exception as exc:
            raise self._err(line.line_no, str(exc)) from exc

    def _encode_alu3(self, line: ParsedLine) -> Instruction:
        self._expect(line, 3)
        dst = self._parse_gpr(line.operands[0])
        src1 = self._parse_reg_alias(line.operands[1])
        src2_token = line.operands[2]
        src2, imm_en = self._parse_reg_or_imm(src2_token)
        pred_ctrl = self._pred_ctrl(line, type_code=self._type(line), imm_en=imm_en)
        src3 = 0
        return self._inst(line, pred_ctrl=pred_ctrl, dst=dst, src1=src1, src2=src2, src3=src3)

    def _encode_cpy(self, line: ParsedLine) -> Instruction:
        self._expect(line, 2)
        dst = self._parse_gpr(line.operands[0])
        src1 = self._parse_reg_alias(line.operands[1])
        pred_ctrl = self._pred_ctrl(line, type_code=self._type(line), imm_en=False)
        return self._inst(line, pred_ctrl=pred_ctrl, dst=dst, src1=src1)

    def _encode_loadi(self, line: ParsedLine) -> Instruction:
        self._expect(line, 2)
        dst = self._parse_gpr(line.operands[0])
        imm = self._parse_int(line.operands[1])
        pred_ctrl = self._pred_ctrl(line, type_code=self._type(line), imm_en=True)
        return self._inst(line, pred_ctrl=pred_ctrl, dst=dst, src1=0xFFFF, src2=imm)

    def _encode_setp(self, line: ParsedLine) -> Instruction:
        self._expect(line, 3)
        dst = self._parse_pred_dest(line.operands[0])
        src1 = self._parse_reg_alias(line.operands[1])
        src2 = self._parse_reg_alias(line.operands[2])
        pred_ctrl = self._pred_ctrl(line, type_code=self._type(line), imm_en=False, ctrl=self._cmp_code(line))
        return self._inst(
            line,
            pred_ctrl=pred_ctrl,
            dst=dst,
            src1=src1,
            src2=src2,
            src3=0,
        )

    def _encode_sfu_unary(self, line: ParsedLine) -> Instruction:
        self._expect(line, 2)
        type_code = self._type(line)
        if type_code != TYPE_CODES["f32"]:
            raise self._err(line.line_no, f"{line.mnemonic} supports .f32 only in AEC-G v1.0")
        dst = self._parse_gpr(line.operands[0])
        src1 = self._parse_reg_alias(line.operands[1])
        subop = 0 if line.mnemonic == "RCP" else 1
        return self._inst(line, pred_ctrl=self._pred_ctrl(line, type_code=type_code, ctrl=subop), dst=dst, src1=src1)

    def _encode_mma(self, line: ParsedLine) -> Instruction:
        self._expect(line, 4)
        suffix_set = set(line.suffixes)
        if "m16n16k16" not in suffix_set or "e4m3" not in suffix_set or "f32" not in suffix_set:
            raise self._err(line.line_no, "MMA supports only .m16n16k16.e4m3.f32 in AEC-G v1.0")
        dst = self._parse_gpr(line.operands[0])
        src1 = self._parse_gpr(line.operands[1])
        src2 = self._parse_gpr(line.operands[2])
        src3 = self._parse_gpr(line.operands[3])
        if dst % 8 or dst > 248:
            raise self._err(line.line_no, "MMA D fragment base must be 8-register aligned and <= R248")
        if src3 % 8 or src3 > 248:
            raise self._err(line.line_no, "MMA C fragment base must be 8-register aligned and <= R248")
        if src1 % 2 or src1 > 254:
            raise self._err(line.line_no, "MMA A fragment base must be even-aligned and <= R254")
        if src2 % 2 or src2 > 254:
            raise self._err(line.line_no, "MMA B fragment base must be even-aligned and <= R254")
        pred_ctrl = self._pred_ctrl(line, type_code=TYPE_CODES["e4m3"], ctrl=0)
        return self._inst(line, pred_ctrl=pred_ctrl, dst=dst, src1=src1, src2=src2, src3=src3)

    def _encode_ld(self, line: ParsedLine) -> Instruction:
        self._expect(line, 2)
        dst = self._parse_gpr(line.operands[0])
        base, offset = self._parse_address(line.operands[1])
        type_code = self._type(line)
        self._check_mem_width(line, dst, type_code, "destination")
        space_code = self._space(line)
        pred_ctrl = self._pred_ctrl(line, type_code=type_code, imm_en=True, space_code=space_code)
        # src3 keeps the legacy RTL width/space field used by wb/lsu tests.
        src3 = (space_code << 8) | self._width_code(type_code)
        return self._inst(line, pred_ctrl=pred_ctrl, dst=dst, src1=base, src2=offset, src3=src3)

    def _encode_st(self, line: ParsedLine) -> Instruction:
        self._expect(line, 2)
        base, offset = self._parse_address(line.operands[0])
        src_reg = self._parse_gpr(line.operands[1])
        type_code = self._type(line)
        self._check_mem_width(line, src_reg, type_code, "source")
        space_code = self._space(line)
        pred_ctrl = self._pred_ctrl(line, type_code=type_code, imm_en=True, space_code=space_code)
        src3 = (src_reg << 16) | (space_code << 8) | self._width_code(type_code)
        return self._inst(line, pred_ctrl=pred_ctrl, dst=0, src1=base, src2=offset, src3=src3)

    def _encode_br(self, line: ParsedLine) -> Instruction:
        self._expect(line, 1)
        target = self._target(line.operands[0], line.line_no)
        return self._inst(line, pred_ctrl=self._pred_ctrl(line), src3=target)

    def _encode_brx(self, line: ParsedLine) -> Instruction:
        self._expect(line, 2)
        pred_name = line.operands[0]
        target = self._target(line.operands[1], line.line_no)
        pred_ctrl = self._pred_ctrl(line, pred_override=pred_name)
        return self._inst(line, pred_ctrl=pred_ctrl, src3=target)

    def _encode_target_only(self, line: ParsedLine) -> Instruction:
        self._expect(line, 1)
        target = self._target(line.operands[0], line.line_no)
        return self._inst(line, pred_ctrl=self._pred_ctrl(line), src3=target)

    def _encode_bar(self, line: ParsedLine) -> Instruction:
        if len(line.operands) not in (1, 2):
            raise self._err(line.line_no, "BAR expects barrier_id[, expected_warps]")
        bid = self._parse_int(line.operands[0])
        expected = self._parse_int(line.operands[1]) if len(line.operands) == 2 else 0
        return self._inst(line, pred_ctrl=self._pred_ctrl(line), dst=bid, src2=expected)

    def _inst(self, line: ParsedLine, pred_ctrl: Optional[int] = None, **fields: int) -> Instruction:
        return Instruction(
            opcode=OPCODES[line.mnemonic],
            pred_ctrl=self._pred_ctrl(line) if pred_ctrl is None else pred_ctrl,
            dst=fields.get("dst", 0),
            src1=fields.get("src1", 0),
            src2=fields.get("src2", 0),
            src3=fields.get("src3", 0),
            line_no=line.line_no,
            text=line.text,
        )

    def _pred_ctrl(
        self,
        line: ParsedLine,
        *,
        pred_override: Optional[str] = None,
        type_code: Optional[int] = None,
        imm_en: bool = False,
        space_code: int = SPACE_CODES["gmem"],
        ctrl: int = 0,
    ) -> int:
        pred_token = pred_override if pred_override is not None else line.pred
        pred_enable = pred_token is not None
        pred_negate = False
        pred = 0
        if pred_token is not None:
            pred = self._parse_pred(pred_token)
            pred_negate = pred_token.strip().startswith("!")
        return PredCtrl(
            pred=pred,
            pred_enable=pred_enable,
            pred_negate=pred_negate,
            type_code=self._type(line) if type_code is None else type_code,
            imm_en=imm_en,
            space_code=space_code,
            ctrl=ctrl,
        ).encode()

    def _type(self, line: ParsedLine) -> int:
        for suffix in line.suffixes:
            if suffix in TYPE_CODES:
                return TYPE_CODES[suffix]
        return TYPE_CODES["u32"]

    def _space(self, line: ParsedLine) -> int:
        for suffix in line.suffixes:
            if suffix in SPACE_CODES:
                return SPACE_CODES[suffix]
        return SPACE_CODES["gmem"]

    def _width_code(self, type_code: int) -> int:
        width = WIDTH_FROM_TYPE.get(type_code)
        if width is None:
            raise AssemblerError(f"type 0x{type_code:x} is not legal for LD/ST")
        return {8: 0, 16: 1, 32: 2, 64: 3}[width]

    def _cmp_code(self, line: ParsedLine) -> int:
        for suffix in line.suffixes:
            if suffix in CMP_CODES:
                return CMP_CODES[suffix]
        raise self._err(line.line_no, f"{line.mnemonic} requires compare suffix .eq/.ne/.lt/.le/.gt/.ge")

    def _check_mem_width(self, line: ParsedLine, reg: int, type_code: int, label: str) -> None:
        if WIDTH_FROM_TYPE.get(type_code) == 64 and reg % 2:
            raise self._err(line.line_no, f"b64 {label} register must be even-aligned")

    def _target(self, token: str, line_no: int) -> int:
        token = token.strip()
        if token in self.labels:
            return self.labels[token]
        return self._parse_int(token)

    def _parse_address(self, token: str) -> Tuple[int, int]:
        text = token.strip()
        match = re.match(r"^\[\s*([^+\]\s]+)\s*(?:\+\s*([+-]?(?:0x[0-9a-fA-F]+|\d+)))?\s*\]$", text)
        if not match:
            raise AssemblerError(f"unsupported address expression {token!r}")
        base = self._parse_reg_alias(match.group(1))
        offset = self._parse_int(match.group(2)) if match.group(2) else 0
        if offset < 0:
            raise AssemblerError("negative address offsets require explicit address arithmetic")
        return base, offset

    def _parse_reg_or_imm(self, token: str) -> Tuple[int, bool]:
        try:
            return self._parse_reg_alias(token), False
        except AssemblerError:
            return self._parse_int(token), True

    def _parse_reg_alias(self, token: str) -> int:
        text = token.strip()
        lower = text.lower()
        if lower in SPECIAL_REGS:
            return SPECIAL_REGS[lower]
        return self._parse_gpr(text)

    def _parse_gpr(self, token: str) -> int:
        text = token.strip()
        match = re.match(r"^[Rr](\d+)$", text)
        if not match:
            raise AssemblerError(f"expected GPR, got {token!r}")
        value = int(match.group(1), 10)
        if value < 0 or value > MAX_GPR:
            raise AssemblerError(f"GPR out of range: R{value}")
        return value

    def _parse_pred(self, token: str) -> int:
        text = token.strip()
        if text.startswith("!"):
            text = text[1:].strip()
        if text.upper() == "PT":
            return 0
        match = re.match(r"^[Pp](\d+)$", text)
        if not match:
            raise AssemblerError(f"expected predicate P0..P7, got {token!r}")
        value = int(match.group(1), 10)
        if value < 0 or value > MAX_PRED:
            raise AssemblerError(f"predicate out of range: P{value}")
        return value

    def _parse_pred_dest(self, token: str) -> int:
        text = token.strip()
        if text.startswith("!") or text.upper() == "PT":
            raise AssemblerError("predicate destination must be P0..P7")
        return self._parse_pred(text)

    def _parse_int(self, token: str) -> int:
        if token is None:
            raise AssemblerError("missing integer")
        text = token.strip()
        value = int(text, 0)
        return value & 0xFFFFFFFF

    def _normalize_mnemonic(self, text: str, line_no: int) -> str:
        value = text.upper()
        aliases = {
            "BRA": "BR",
            "IADD": "ADD",
            "IMUL": "MUL",
            "MOV": "CPY",
        }
        value = aliases.get(value, value)
        if value not in OPCODES:
            raise self._err(line_no, f"unknown opcode {text}")
        return value

    def _expect(self, line: ParsedLine, count: int) -> None:
        if len(line.operands) != count:
            raise self._err(line.line_no, f"{line.mnemonic} expects {count} operands, got {len(line.operands)}")

    def _split_operands(self, rest: str) -> List[str]:
        out: List[str] = []
        cur: List[str] = []
        depth = 0
        for ch in rest:
            if ch in "[{(":
                depth += 1
            elif ch in "]})":
                depth -= 1
            if ch == "," and depth == 0:
                out.append("".join(cur).strip())
                cur = []
            else:
                cur.append(ch)
        if cur:
            out.append("".join(cur).strip())
        return out

    def _err(self, line_no: int, msg: str) -> AssemblerError:
        return AssemblerError(f"line {line_no}: {msg}")


def write_hex(path: Path, instructions: Sequence[Instruction]) -> None:
    path.write_text("\n".join(inst.to_hex() for inst in instructions) + "\n", encoding="ascii")


def write_aecbin(path: Path, instructions: Sequence[Instruction]) -> None:
    path.write_bytes(b"".join(inst.to_aecbin() for inst in instructions))


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Assemble AEC-G assembly into 128-bit machine code")
    parser.add_argument("input", type=Path)
    parser.add_argument("-o", "--output", type=Path, required=True)
    parser.add_argument("--format", choices=("hex", "aecbin"), default=None)
    args = parser.parse_args(argv)

    try:
        text = args.input.read_text(encoding="utf-8")
        instructions = Assembler().assemble_text(text)
        out_format = args.format
        if out_format is None:
            out_format = "aecbin" if args.output.suffix == ".aecbin" else "hex"
        if out_format == "hex":
            write_hex(args.output, instructions)
        else:
            write_aecbin(args.output, instructions)
        return 0
    except (OSError, AssemblerError, ValueError) as exc:
        sys.stderr.write(f"aec-as: error: {exc}\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
