import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "compiler"))

from compiler import CompileError, Compiler  # noqa: E402
from aec_assembler import Assembler  # noqa: E402


def _ptx(body):
    return """.version 9.3
.target sm_80
.address_size 64
.visible .entry k()
{
.reg .u32 %r<16>;
""" + body + """
ret;
}
"""


def _compile(body):
    return Compiler().compile_text(_ptx(body))


def test_b128_load_store_lower_to_legal_32bit_ops():
    blob, report = _compile("""
ld.global.b128 {%r1,%r2,%r3,%r4}, [%r0+0];
st.global.b128 [%r0+16], {%r1,%r2,%r3,%r4};
""")
    assert len(blob) % 16 == 0
    mnems = [x["mnemonic"] for x in report["instructions"]]
    assert mnems.count("LD") == 4
    assert mnems.count("ST") == 4
    assert "b128" not in report["used_extensions"]


def test_b64_reuses_odd_existing_register_is_rejected():
    try:
        _compile("""
mov.u32 %r0, 0;
mov.u32 %r1, 0;
ld.global.u64 %r1, [%r0+0];
""")
    except CompileError as exc:
        assert "even-aligned" in str(exc)
    else:
        raise AssertionError("expected odd b64 destination to be rejected")


def test_mma_reuses_misaligned_existing_fragment_register_is_rejected():
    try:
        _compile("""
mov.u32 %r0, 0;
mov.u32 %r1, 0;
mma.sync.aligned.m16n16k16.row.col.e4m3.e4m3.f32 %r1, %r0, %r2, %r8;
""")
    except CompileError as exc:
        assert "aligned" in str(exc)
    else:
        raise AssertionError("expected misaligned MMA D fragment to be rejected")


def test_stage7_integer_logic_ops_lower_to_contract_opcodes():
    blob, report = _compile("""
sub.u32 %r3, %r1, %r2;
and.b32 %r4, %r3, 255;
or.b32 %r5, %r4, %r1;
xor.b32 %r6, %r5, %r2;
shl.b32 %r7, %r6, 33;
shr.u32 %r8, %r7, 1;
""")
    assert len(blob) % 16 == 0
    mnems = [x["mnemonic"] for x in report["instructions"]]
    assert mnems[:6] == ["SUB.u32", "AND.b32", "OR.b32", "XOR.b32", "SHL.b32", "SHR.b32"]


def test_memory_space_codes_match_assembler_rtl_contract():
    _blob, report = _compile("""
ld.global.u32 %r1, [%r0+0];
ld.param.u32 %r2, [%r0+4];
ld.shared.u32 %r3, [%r0+8];
ld.local.u32 %r4, [%r0+12];
ld.const.u32 %r5, [%r0+16];
""")
    ctrls = [inst["src3"] for inst in report["instructions"][:5]]
    assert ctrls == [0x002, 0x102, 0x202, 0x302, 0x402]


def test_assembler_bar_sync_uses_dst_field_for_barrier_id():
    inst = Assembler().assemble_text("BAR.SYNC 3, 0\n")[0]
    word = inst.encode_int()
    assert ((word >> 80) & 0xFF) == 3
    assert ((word >> 64) & 0xFFFF) == 0
    assert ((word >> 32) & 0xFFFF) == 0


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
    print("compiler tests passed")

