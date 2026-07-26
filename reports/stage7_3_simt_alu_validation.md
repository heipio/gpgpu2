# Stage 7.3 SIMT ALU Validation

Date: 2026-07-26

## Implemented

- Extended `rtl/aec_pkg.sv` with Stage 7 ALU opcodes:
  `SUB=0x000a`, `AND=0x000b`, `OR=0x000c`, `XOR=0x000d`,
  `SHL=0x000e`, and `SHR=0x000f`.
- Extended `rtl/alu_lane.sv` with wrapping integer subtract, bitwise logic, and
  logical shifts. Shift amounts are masked with `& 31`.
- Updated `rtl/wb_stage.sv` so the new ALU opcodes write back to VRF.
- Updated `rtl/ex_stage.sv` to support `CPY.u32 Rd, %laneid`.
  - The hardware contract follows the assembler's existing special register
    encoding: `%laneid = 0x0100`.
  - Returned value is the logical lane id: `{beat, physical_lane}`.
- Updated `rtl/cu_top.sv` to preserve the full 16-bit `src1` selector into EX
  so special register encodings are not truncated.
- Updated `rtl/tb_system.sv` default active mask to `32'h000000ff` for true
  8-lane execution in the command-file testbench.
- Added `tests/alu_simt.asm`, an 8-lane SIMT kernel using `%laneid` to compute
  independent addresses.
- Added `tests/run_alu_simt_e2e.py`, which checks:
  `expected[i] = ((A[i] - B[i]) & 0xffffffff) ^ i`.
- Updated `aec_g_isa_v1.json` so the machine-readable ISA includes the new
  ALU opcodes and special register encodings.

## Validation

Local:

- `python -m json.tool aec_g_isa_v1.json` passed.
- `python tests/test_assembler.py` passed.
- `python tests/run_vector_add_e2e.py --skip-xsim` generated commands.
- `python tests/run_alu_simt_e2e.py --skip-xsim` generated commands.

Remote XSim 2023.1:

```text
[SYSTEM TEST] PASS host_cmds complete
ALU_SIMT_E2E PASS out=['0x6539832', '0x7a0b0c6b', '0x244c4b32', '0x705f7c0', '0xbb384aff', '0x8cc9c34e', '0x58b92abc', '0x4ffb7291']
```

Stage 7.2 regression:

```text
[SYSTEM TEST] PASS host_cmds complete
VECTOR_ADD_E2E PASS a=1390851128 b=647892279 out=2038743407
```

## Notes

- The prompt mentioned `%laneid = 0x0104`, but the existing assembler contract
  already used `%laneid = 0x0100`. The final implementation keeps the existing
  software/hardware contract consistent.
- `%laneid` is implemented as logical lane id, not merely physical lane id, so
  later beats naturally produce lanes 8..31.
