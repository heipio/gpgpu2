# Stage 8 SFU RCP/EXP2 vector test.
# Parameters at 0x4000:
#   [0] input base, [1] RCP output base, [2] EXP2 output base

LD.pmem.u32 R10, [R0 + 0x4000]
LD.pmem.u32 R11, [R0 + 0x4004]
LD.pmem.u32 R12, [R0 + 0x4008]

CPY.u32 R1, %laneid
SHL.b32 R2, R1, 2

ADD.u32 R3, R10, R2
ADD.u32 R4, R11, R2
ADD.u32 R5, R12, R2

LD.gmem.u32 R6, [R3 + 0]
RCP.f32 R7, R6
EXP2.f32 R8, R6
ST.gmem.u32 [R4 + 0], R7
ST.gmem.u32 [R5 + 0], R8
HALT
