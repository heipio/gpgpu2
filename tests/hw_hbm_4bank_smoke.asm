# Board smoke program: exercise all four routed AEC HBM address regions.
# Router bits [31:30] select m_axi_gmem0..3, linked to HBM[16]..HBM[19].
LOADI.u32 R10, 0x00001000
LOADI.u32 R11, 0x40001000
LOADI.u32 R12, 0x80001000
LOADI.u32 R13, 0xc0001000
LD.gmem.u32 R1, [R10 + 0]
LD.gmem.u32 R2, [R11 + 0]
ADD.u32 R3, R1, R2
ST.gmem.u32 [R12 + 0], R3
ST.gmem.u32 [R13 + 0], R3
FENCE.device
HALT
NOP
