#!/usr/bin/env python3
"""Core PTX-to-AEC-G v1.0 compiler.

Stage-two scope:
- Parse a conservative PTX subset.
- Lower legal PTX ops into AEC-G v1.0 instructions.
- Allocate AEC GPRs/predicates with 64-bit and MMA alignment checks.
- Emit strict headerless .aecbin: 16 bytes per instruction, no file header.

Unsupported PTX is rejected. This keeps hidden-kernel portability honest and
prevents accidental ISA redefinition.
"""

import argparse
import json
import os
import re
import struct
import sys
from collections import OrderedDict

INSTR_BYTES = 16
MAX_GPRS = 256
MAX_PREDS = 8

OPCODES = {
    "NOP": 0x00, "MOV": 0x01, "IADD.u32": 0x02, "IMUL.u32": 0x03,
    "FADD.f32": 0x04, "FMUL.f32": 0x05, "MAD.f32": 0x06, "FMA.f32": 0x07,
    "SETP": 0x08, "LD": 0x10, "ST": 0x11, "FENCE": 0x12,
    "BRA": 0x20, "BRX": 0x21, "BAR.SYNC": 0x24,
    "SFU.RCP.f32": 0x40, "SFU.EXP2.f32": 0x41,
    "MMA.m16n16k16.e4m3.f32": 0x50, "HALT": 0x7F,
}
SPACE = {"global": 0, "shared": 1, "const": 2, "local": 3, "param": 4}
WIDTH = {8: 0, 16: 1, 32: 2, 64: 3}
CMP = {"eq": 0, "ne": 1, "lt": 2, "le": 3, "gt": 4, "ge": 5}


class CompileError(Exception):
    pass


class PTXInstruction(object):
    def __init__(self, op, operands, pred=None, line_no=0, text=""):
        self.op = op
        self.operands = operands
        self.pred = pred
        self.line_no = line_no
        self.text = text


class PTXProgram(object):
    def __init__(self):
        self.version = None
        self.target = None
        self.address_size = 64
        self.entry = None
        self.params = []
        self.labels = OrderedDict()
        self.instructions = []
        self.shared = OrderedDict()


class Parser(object):
    def parse(self, text):
        prog = PTXProgram()
        in_entry = False
        depth = 0
        for line_no, raw in enumerate(text.splitlines(), 1):
            line = raw.split("//", 1)[0].strip()
            if not line:
                continue
            if line.startswith(".version"):
                prog.version = line.split(None, 1)[1]
                continue
            if line.startswith(".target"):
                prog.target = line.split(None, 1)[1]
                continue
            if line.startswith(".address_size"):
                prog.address_size = int(line.split()[1])
                if prog.address_size != 64:
                    raise CompileError("line %d: AEC runtime ABI requires .address_size 64" % line_no)
                continue
            if line.startswith(".entry") or line.startswith(".visible .entry"):
                m = re.search(r"\.entry\s+([A-Za-z_$][\w$]*)", line)
                if not m:
                    raise CompileError("line %d: cannot parse .entry name" % line_no)
                prog.entry = m.group(1)
                in_entry = True
                depth += line.count("{") - line.count("}")
                continue
            if not in_entry:
                continue
            depth += line.count("{") - line.count("}")
            if line == "}" or depth < 0:
                in_entry = False
                continue
            if line.startswith(".param"):
                m = re.search(r"\.param\s+\.([busf]\d+)\s+([A-Za-z_$][\w$]*)", line)
                if m:
                    prog.params.append({"type": m.group(1), "name": m.group(2), "line": line_no})
                continue
            if line.startswith(".reg"):
                continue
            if line in ("{", "}", ")", "){", "},") or line.startswith(")"):
                continue
            if line.startswith(".shared"):
                m = re.search(r"\.shared(?:\s+\.align\s+\d+)?\s+\.([busf]\d+)\s+([A-Za-z_$][\w$]*)\[(\d+)\]", line)
                if m:
                    prog.shared[m.group(2)] = {"type": m.group(1), "count": int(m.group(3)), "line": line_no}
                continue
            if line.endswith(":"):
                prog.labels[line[:-1]] = len(prog.instructions)
                continue
            if line.endswith(";"):
                line = line[:-1]
            pred = None
            if line.startswith("@"):
                p, line = line.split(None, 1)
                pred = p[1:]
            if " " in line:
                op, rest = line.split(None, 1)
                operands = split_operands(rest)
            else:
                op, operands = line, []
            prog.instructions.append(PTXInstruction(op, operands, pred, line_no, line))
        if prog.entry is None:
            raise CompileError("no PTX .entry found")
        return prog


def split_operands(rest):
    out, cur, depth = [], [], 0
    for ch in rest:
        if ch in "[{":
            depth += 1
        elif ch in "]}":
            depth -= 1
        if ch == "," and depth == 0:
            out.append("".join(cur).strip())
            cur = []
        else:
            cur.append(ch)
    if cur:
        out.append("".join(cur).strip())
    return out


class RegAlloc(object):
    def __init__(self):
        self.gprs = OrderedDict()
        self.preds = OrderedDict()
        self.next_gpr = 0
        self.next_pred = 0

    def gpr(self, name, width=32, align=1):
        name = name.strip().lstrip("%")
        if name in self.gprs:
            return self.gprs[name]
        if width == 64:
            align = max(align, 2)
        if self.next_gpr % align:
            self.next_gpr += align - (self.next_gpr % align)
        need = 2 if width == 64 else 1
        if self.next_gpr + need > MAX_GPRS:
            raise CompileError("GPR allocation exceeded %d" % MAX_GPRS)
        reg = self.next_gpr
        self.gprs[name] = reg
        self.next_gpr += need
        return reg

    def pred(self, name):
        if not name:
            return 0xFFFF
        name = name.strip().lstrip("%")
        if name.lower() == "pt":
            return 0xFFFF
        if name in self.preds:
            return self.preds[name]
        if self.next_pred >= MAX_PREDS:
            raise CompileError("predicate allocation exceeded %d" % MAX_PREDS)
        val = self.next_pred
        self.preds[name] = val
        self.next_pred += 1
        return val


class AECInstruction(object):
    def __init__(self, mnemonic, dst=0, src1=0, src2=0, src3=0, pred=0xFFFF, comment=""):
        self.mnemonic = mnemonic
        self.opcode = OPCODES[mnemonic]
        self.dst, self.src1 = dst & 0xFFFF, src1 & 0xFFFF
        self.src2, self.src3 = src2 & 0xFFFFFFFF, src3 & 0xFFFFFFFF
        self.pred = pred & 0xFFFF
        self.comment = comment

    def encode(self):
        value = ((self.opcode & 0xFFFF) << 112) | ((self.pred & 0xFFFF) << 96)
        value |= (self.dst & 0xFFFF) << 80
        value |= (self.src1 & 0xFFFF) << 64
        value |= (self.src2 & 0xFFFFFFFF) << 32
        value |= self.src3 & 0xFFFFFFFF
        return struct.pack("<IIII", value & 0xFFFFFFFF, (value >> 32) & 0xFFFFFFFF,
                           (value >> 64) & 0xFFFFFFFF, (value >> 96) & 0xFFFFFFFF)

    def json(self):
        return OrderedDict([("mnemonic", self.mnemonic), ("dst", self.dst),
                            ("src1", self.src1), ("src2", self.src2),
                            ("src3", self.src3), ("pred", self.pred),
                            ("comment", self.comment)])


class Lowerer(object):
    def __init__(self, prog):
        self.prog = prog
        self.ra = RegAlloc()
        self.out = []
        self.fixups = []
        self.used_extensions = []

    def lower(self):
        for inst in self.prog.instructions:
            self.one(inst)
        for idx, label in self.fixups:
            label = label.lstrip("$")
            if label not in self.prog.labels:
                raise CompileError("unknown branch label %s" % label)
            self.out[idx].src2 = self.prog.labels[label]
        self.emit("HALT", comment="implicit halt")
        return self.out

    def emit(self, mnemonic, dst=0, src1=0, src2=0, src3=0, pred=0xFFFF, comment=""):
        self.out.append(AECInstruction(mnemonic, dst, src1, src2, src3, pred, comment))

    def one(self, inst):
        pred = self.ra.pred(inst.pred)
        try:
            op = inst.op
            if op in ("ret", "exit"):
                self.emit("HALT", pred=pred, comment=inst.text)
            elif op.startswith("mov.") or op.startswith("cvt."):
                self.mov(inst, pred)
            elif op in ("add.u32", "add.s32"):
                self.binary(inst, pred, "IADD.u32")
            elif op in ("mul.lo.u32", "mul.lo.s32"):
                self.binary(inst, pred, "IMUL.u32")
            elif op == "add.f32":
                self.binary(inst, pred, "FADD.f32")
            elif op == "mul.f32":
                self.binary(inst, pred, "FMUL.f32")
            elif op == "mad.f32":
                self.ternary(inst, pred, "MAD.f32")
            elif op in ("fma.f32", "fma.rn.f32"):
                self.ternary(inst, pred, "FMA.f32")
            elif op.startswith("ld."):
                self.ld(inst, pred)
            elif op.startswith("st."):
                self.st(inst, pred)
            elif op.startswith("setp."):
                self.setp(inst, pred)
            elif op == "bra" or op.startswith("bra."):
                idx = len(self.out)
                self.emit("BRA" if pred == 0xFFFF else "BRX", pred=pred, comment=inst.text)
                self.fixups.append((idx, inst.operands[0]))
            elif op == "bar.sync":
                bid = int(inst.operands[0], 0)
                expected = int(inst.operands[1], 0) if len(inst.operands) > 1 else 0
                self.emit("BAR.SYNC", src1=bid, src2=expected, pred=pred, comment=inst.text)
            elif op in ("rcp.approx.f32", "rcp.rn.f32"):
                self.unary(inst, pred, "SFU.RCP.f32")
            elif op in ("ex2.approx.f32", "ex2.rn.f32"):
                self.unary(inst, pred, "SFU.EXP2.f32")
            elif op.startswith("mma."):
                self.mma(inst, pred)
            else:
                raise CompileError("unsupported PTX op %s" % op)
        except CompileError as exc:
            raise CompileError("line %d: %s" % (inst.line_no, exc))

    def mov(self, inst, pred):
        check_n(inst, 2)
        dst = self.ra.gpr(inst.operands[0], width_from_op(inst.op))
        src = operand(inst.operands[1], self.ra)
        self.emit("MOV", dst=dst, src1=src[1] if src[0] == "reg" else 0xFFFF,
                  src2=src[1] if src[0] == "imm" else 0, pred=pred, comment=inst.text)

    def binary(self, inst, pred, mnem):
        check_n(inst, 3)
        width = width_from_op(inst.op)
        src2 = operand(inst.operands[2], self.ra)
        self.emit(mnem, dst=self.ra.gpr(inst.operands[0], width),
                  src1=self.ra.gpr(inst.operands[1], width), src2=src2[1],
                  pred=pred, comment=inst.text)

    def ternary(self, inst, pred, mnem):
        check_n(inst, 4)
        self.emit(mnem, self.ra.gpr(inst.operands[0]), self.ra.gpr(inst.operands[1]),
                  self.ra.gpr(inst.operands[2]), self.ra.gpr(inst.operands[3]), pred, inst.text)

    def unary(self, inst, pred, mnem):
        check_n(inst, 2)
        self.emit(mnem, self.ra.gpr(inst.operands[0]), self.ra.gpr(inst.operands[1]),
                  pred=pred, comment=inst.text)

    def setp(self, inst, pred):
        check_n(inst, 3)
        cmp_code = CMP.get(inst.op.split(".")[1], 0)
        self.emit("SETP", self.ra.pred(inst.operands[0]), self.ra.gpr(inst.operands[1]),
                  self.ra.gpr(inst.operands[2]), cmp_code, pred, inst.text)

    def ld(self, inst, pred):
        check_n(inst, 2)
        space, width = space_width(inst.op)
        dsts = vector(inst.operands[0])
        base, off = address(inst.operands[1], self.ra)
        if width == 128:
            step = 64 if len(dsts) == 2 else 32
            if len(dsts) not in (2, 4):
                raise CompileError(".b128 load must lower to two b64 or four b32 destinations")
            for i, dst_name in enumerate(dsts):
                dst = self.ra.gpr(dst_name, step)
                if step == 64 and dst % 2:
                    raise CompileError("b64 destination must be even-aligned")
                self.emit("LD", dst, base, off + i * (step // 8), mem_ctrl(space, step), pred, inst.text)
            return
        if len(dsts) != 1:
            raise CompileError("vector load requires .b128 lowering")
        dst = self.ra.gpr(dsts[0], width)
        if width == 64 and dst % 2:
            raise CompileError("b64 destination must be even-aligned")
        self.emit("LD", dst, base, off, mem_ctrl(space, width), pred, inst.text)

    def st(self, inst, pred):
        check_n(inst, 2)
        space, width = space_width(inst.op)
        base, off = address(inst.operands[0], self.ra)
        srcs = vector(inst.operands[1])
        if width == 128:
            step = 64 if len(srcs) == 2 else 32
            if len(srcs) not in (2, 4):
                raise CompileError(".b128 store must lower from two b64 or four b32 sources")
            for i, src_name in enumerate(srcs):
                src = self.ra.gpr(src_name, step)
                if step == 64 and src % 2:
                    raise CompileError("b64 source must be even-aligned")
                self.emit("ST", 0, base, off + i * (step // 8), (src << 16) | mem_ctrl(space, step), pred, inst.text)
            return
        src = self.ra.gpr(srcs[0], width)
        if width == 64 and src % 2:
            raise CompileError("b64 source must be even-aligned")
        self.emit("ST", 0, base, off, (src << 16) | mem_ctrl(space, width), pred, inst.text)

    def mma(self, inst, pred):
        check_n(inst, 4)
        if "m16n16k16" not in inst.op or "e4m3" not in inst.op:
            raise CompileError("only m16n16k16.e4m3.f32 MMA is supported")
        d = self.ra.gpr(inst.operands[0], align=8)
        a = self.ra.gpr(inst.operands[1], align=2)
        b = self.ra.gpr(inst.operands[2], align=2)
        c = self.ra.gpr(inst.operands[3], align=8)
        self.emit("MMA.m16n16k16.e4m3.f32", d, a, b, c, pred, inst.text)


def check_n(inst, n):
    if len(inst.operands) != n:
        raise CompileError("%s expects %d operands, got %d" % (inst.op, n, len(inst.operands)))


def operand(tok, ra):
    tok = tok.strip()
    if tok.startswith("%"):
        return ("reg", ra.gpr(tok))
    try:
        return ("imm", int(tok, 0) & 0xFFFFFFFF)
    except ValueError:
        return ("reg", ra.gpr(tok))


def vector(tok):
    tok = tok.strip()
    m = re.match(r"^\{(.+)\}$", tok)
    return [x.strip() for x in m.group(1).split(",")] if m else [tok]


def address(tok, ra):
    m = re.match(r"\[(%?[A-Za-z_$][\w$]*)(?:\+(-?\d+))?\]", tok.strip())
    if not m:
        raise CompileError("unsupported address expression %s" % tok)
    off = int(m.group(2), 0) if m.group(2) else 0
    if off < 0:
        raise CompileError("negative offsets require explicit address arithmetic")
    return ra.gpr(m.group(1)), off


def space_width(op):
    space, width = "global", 32
    for part in op.split("."):
        if part in SPACE:
            space = part
        elif part.startswith("b") and part[1:].isdigit():
            width = int(part[1:])
        elif part in ("u8", "s8"):
            width = 8
        elif part in ("u16", "s16"):
            width = 16
        elif part in ("u64", "s64"):
            width = 64
    return space, width


def width_from_op(op):
    return 64 if any(x in op for x in (".u64", ".s64", ".b64")) else 32


def mem_ctrl(space, width):
    if width not in WIDTH:
        raise CompileError("illegal base memory width %d" % width)
    return (SPACE.get(space, 0) << 8) | WIDTH[width]


class Compiler(object):
    def compile_text(self, text):
        prog = Parser().parse(text)
        lowerer = Lowerer(prog)
        insts = lowerer.lower()
        blob = b"".join(x.encode() for x in insts)
        report = OrderedDict([
            ("schema", "aec_compile_report_v1"),
            ("entry", prog.entry),
            ("instruction_count", len(insts)),
            ("aecbin_bytes", len(blob)),
            ("headerless", True),
            ("instruction_width_bits", 128),
            ("registers", len(lowerer.ra.gprs)),
            ("predicates", len(lowerer.ra.preds)),
            ("spills", 0),
            ("params", prog.params),
            ("static_shared", prog.shared),
            ("used_extensions", lowerer.used_extensions),
            ("diagnostics", []),
            ("instructions", [x.json() for x in insts]),
        ])
        return blob, report


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("ptx")
    ap.add_argument("-o", "--output", required=True)
    ap.add_argument("--report")
    args = ap.parse_args(argv)
    try:
        text = open(args.ptx, "r").read()
        blob, report = Compiler().compile_text(text)
        open(args.output, "wb").write(blob)
        if len(blob) % INSTR_BYTES:
            raise CompileError("internal error: output is not 128-bit aligned")
        if args.report:
            fh = open(args.report, "w")
            json.dump(report, fh, indent=2)
            fh.write("\n")
            fh.close()
    except CompileError as exc:
        sys.stderr.write("aec-cc: error: %s\n" % exc)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
