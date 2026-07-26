# AEC-G Stage 7.1 assembler smoke test.
# Scalar lane-0 vector-add style kernel matching the Stage 6 host ABI:
# pmem[0x4000] = source A address
# pmem[0x4004] = source B address
# pmem[0x4008] = destination address

LD.pmem.u32 R1, [R0 + 0x4000]
LD.pmem.u32 R2, [R0 + 0x4004]
LD.pmem.u32 R3, [R0 + 0x4008]
LD.gmem.u32 R4, [R1 + 0]
LD.gmem.u32 R5, [R2 + 0]
ADD.u32 R6, R4, R5
ST.gmem.u32 [R3 + 0], R6
HALT
