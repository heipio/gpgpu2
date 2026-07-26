# Stage 7.4 predicate gating test.
# Parameters at pmem[0x4000..0x4008]: A base, B base, C base.
# Lanes 0..3 satisfy P0 and store A+B; lanes 4..7 must leave C untouched.

LD.pmem.u32 R10, [R0 + 0x4000]
LD.pmem.u32 R11, [R0 + 0x4004]
LD.pmem.u32 R12, [R0 + 0x4008]
CPY.u32 R1, %laneid
LOADI.u32 R2, 4
SETP.lt.u32 P0, R1, R2
SHL.b32 R3, R1, 2
ADD.u32 R4, R10, R3
ADD.u32 R5, R11, R3
ADD.u32 R6, R12, R3
@P0 LD.gmem.u32 R7, [R4 + 0]
@P0 LD.gmem.u32 R8, [R5 + 0]
@P0 ADD.u32 R9, R7, R8
@P0 ST.gmem.u32 [R6 + 0], R9
HALT
