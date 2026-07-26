import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tests"))

from simulator import AECGSimulator  # noqa: E402


def test_brx_splits_masks_and_pushes_fallthrough_reconvergence():
    sim = AECGSimulator()
    sim.active_mask = 0xF
    sim.pred[0][0] = True
    sim.pred[1][0] = False
    sim.pred[2][0] = True
    sim.pred[3][0] = False
    sim.pc = 10
    sim.brx(predicate=0, target_pc=40, fallthrough_pc=11)
    assert sim.pc == 40
    assert sim.active_mask == 0b0101
    assert sim.reconv_stack == [(11, 0b1010)]


def test_sync_restores_reconvergence_pc_and_mask():
    sim = AECGSimulator()
    sim.active_mask = 0b0101
    sim.push_reconvergence(11, 0b1010)
    sim.sync()
    assert sim.pc == 11
    assert sim.active_mask == 0b1010
    assert sim.faults == []


def test_sync_underflow_faults():
    sim = AECGSimulator()
    sim.sync()
    assert sim.faults == ["SIMT_STACK_FAULT"]


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
    print("sim ctrl tests passed")
