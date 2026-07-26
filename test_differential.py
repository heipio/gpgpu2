import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "compiler"))
sys.path.insert(0, os.path.join(ROOT, "tests"))

from compiler import Compiler  # noqa: E402
from simulator import AECGSimulator  # noqa: E402


VECTOR_ADD_PTX = """.version 9.3
.target sm_80
.address_size 64
.visible .entry vadd()
{
.reg .u32 %r<8>;
ld.global.u32 %r3, [%r0+0];
ld.global.u32 %r4, [%r1+0];
add.u32 %r5, %r3, %r4;
st.global.u32 [%r2+0], %r5;
ret;
}
"""


def test_vector_add_ptx_to_aecbin_to_simulator():
    blob, report = Compiler().compile_text(VECTOR_ADD_PTX)
    assert len(blob) % 16 == 0
    assert report["headerless"] is True

    regs = report["register_map"]
    sim = AECGSimulator()
    sim.active_mask = 0x1
    sim.gpr[0][regs["r0"]] = 0x1000
    sim.gpr[0][regs["r1"]] = 0x2000
    sim.gpr[0][regs["r2"]] = 0x3000

    a = 123
    b = 456
    sim.store_u32(0x1000, a)
    sim.store_u32(0x2000, b)
    sim.execute_aecbin(blob)

    assert sim.faults == []
    assert sim.load_u32(0x3000) == (a + b) & 0xFFFFFFFF


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
    print("differential tests passed")
