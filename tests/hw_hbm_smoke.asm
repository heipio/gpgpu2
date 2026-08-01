# Minimal board-life-cycle program: all addresses are in HBM port 0.
LOADI.u32 R10, 0x1000
LOADI.u32 R11, 0x2000
LOADI.u32 R12, 0x3000
LD.gmem.u32 R1, [R10 + 0]
LD.gmem.u32 R2, [R11 + 0]
ADD.u32 R3, R1, R2
ST.gmem.u32 [R12 + 0], R3
FENCE.device
HALT
