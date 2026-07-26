# AEC-G Stage 7.3 SIMT ALU kernel.
# pmem[0x4000] = source A base address
# pmem[0x4004] = source B base address
# pmem[0x4008] = destination C base address

LD.pmem.u32 R10, [R0 + 0x4000]
LD.pmem.u32 R11, [R0 + 0x4004]
LD.pmem.u32 R12, [R0 + 0x4008]
CPY.u32 R1, %laneid
SHL.b32 R2, R1, 2
ADD.u32 R3, R10, R2
ADD.u32 R4, R11, R2
ADD.u32 R5, R12, R2
LD.gmem.u32 R6, [R3 + 0]
LD.gmem.u32 R7, [R4 + 0]
SUB.u32 R8, R6, R7
XOR.b32 R9, R8, R1
ST.gmem.u32 [R5 + 0], R9
HALT
