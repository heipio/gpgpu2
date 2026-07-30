import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "compiler"))

from aec_assembler import Assembler


def test_vector_add_exact_hex():
    asm = (ROOT / "tests" / "vector_add.asm").read_text()
    encoded = [inst.to_hex() for inst in Assembler().assemble_text(asm)]
    assert encoded == [
        "00300890000100000000400000000102",
        "00300890000200000000400400000102",
        "00300890000300000000400800000102",
        "00300090000400010000000000000002",
        "00300090000500020000000000000002",
        "00010010000600040000000500000000",
        "00310090000000030000000000060002",
        "00450010000000000000000000000000",
    ]


def test_labels_and_predicate_encode():
    encoded = [inst.to_hex() for inst in Assembler().assemble_text("""
start:
  @P1 BRX P1, done
  BR start
done:
    HALT
""")]
    assert encoded[0] == "00418011000000000000000000000002"
    assert encoded[1] == "00400010000000000000000000000000"
    assert encoded[2] == "00450010000000000000000000000000"


def test_b64_alignment_rejected():
    try:
        Assembler().assemble_text("LD.gmem.u64 R1, [R0 + 0]")
    except ValueError as exc:
        assert "even-aligned" in str(exc)
    else:
        raise AssertionError("expected b64 odd-register diagnostic")


def test_setp_and_predicated_instruction_encode():
    encoded = [inst.to_hex() for inst in Assembler().assemble_text("""
      CPY.u32 R1, %laneid
      LOADI.u32 R2, 4
      SETP.lt.u32 P0, R1, R2
      @P0 ADD.u32 R3, R1, R2
      @!P0 ST.gmem.u32 [R10 + 0], R3
    """)]
    assert encoded[2] == "00200210000000010000000200000000"
    assert encoded[3].startswith("00018010")
    assert encoded[4].startswith("0031c090")


def test_stage9_mma_encoding_matches_official_contract():
    inst = Assembler().assemble_text("MMA.m16n16k16.e4m3.f32 R16, R2, R4, R24\n")[0]
    assert inst.opcode == 0x0070
    assert inst.pred_ctrl == 0x0058
    assert inst.dst == 16
    assert inst.src1 == 2
    assert inst.src2 == 4
    assert inst.src3 == 24


def test_stage9_mma_alignment_is_rejected():
    try:
        Assembler().assemble_text("MMA.m16n16k16.e4m3.f32 R15, R2, R4, R24\n")
    except ValueError as exc:
        assert "D fragment" in str(exc)
    else:
        raise AssertionError("expected misaligned MMA D fragment to be rejected")


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
    print("assembler tests passed")
