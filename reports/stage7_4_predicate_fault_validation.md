# Stage 7.4 Predicate And Fault/Status CSR Validation

Date: 2026-07-26

## Contract Check

- ISA JSON used: `aec_g_isa_v1.json`. The requested `compiler/aec_g_isa_v1.json` path does not exist in the current repository; the root JSON is the active machine-readable ISA contract.
- 128-bit instruction layout:
  - `opcode`: bits `[127:112]`
  - `pred_ctrl`: bits `[111:96]`
  - `dst`: bits `[95:80]`
  - `src1`: bits `[79:64]`
  - `src2_or_imm32`: bits `[63:32]`
  - `src3_or_immext`: bits `[31:0]`
- Predicate control layout:
  - `pred_index`: bits `[98:96]`, encodes `P0..P7`
  - `pred_negate`: bit `[99]`, used by `@!P`
  - `type_code`: bits `[103:100]`
  - `imm_enable`: bit `[104]`
  - `space_code`: bits `[107:105]`
  - `ctrl`: bits `[110:108]`
  - `pred_enable`: bit `[111]`
  - absent predicate prefix maps to `PT`, the always-true pseudo-predicate
- Predicate registers: 8 lane-private predicate registers, `P0..P7`, plus `PT`.
- Predicate-generating instructions:
  - `SETP`, opcode `0x08`, syntax implemented as `SETP.<cmp>.<type> Pd, Ra, Rb`
  - `CMPP`, opcode `0x09`, syntax implemented as `CMPP.<cmp>.<type> Pd, Ra, Rb`
  - comparison codes: `eq=0`, `ne=1`, `lt=2`, `le=3`, `gt=4`, `ge=5`

## CSR ABI

The official local contest files require explicit fault/status reporting but do not provide a fuller address map beyond the existing project `CTRL`, `PC`, and `IMEM` windows. Stage 7.4 freezes the project-local ABI in `aec_g_isa_v1.json`:

- `0x0000 CSR_CTRL`: bit0 `START` W1 pulse, bit1 `DONE` W1C/read, bit2 `FAULT` W1C/read
- `0x0004 CSR_PC`: bits `[15:0]` kernel start PC
- `0x0008 CSR_STATUS`: bit0 `RUNNING`, bit1 `DONE`, bit2 `FAULT`
- `0x000c CSR_FAULT_CODE`: `aec_fault_e`
- `0x0010 CSR_FAULT_PC`: first latched fault PC
- `0x1000..0x1fff IMEM_WINDOW`: 32-bit AXI-Lite access to 128-bit instruction memory

## Implemented RTL Changes

- Added `rtl/id_stage.sv` as the decode contract stage, wrapping `fetch_decode` and producing `pred_sel_o` plus `illegal_opcode_o`.
- Fixed `rtl/fetch_decode.sv` so predicate enable is exactly `instr[111]`, not `|pred_ctrl`.
- Fixed `rtl/prf_top.sv` so `@!P` returns the bitwise inverse of the selected predicate register for the current beat.
- Updated `rtl/ex_stage.sv`:
  - accepts a PRF-sourced predicate mask
  - computes `effective_mask = active_mask & predicate_mask`
  - drives all EX/WB/LSU side effects through this effective mask
  - implements PRF writeback for `SETP` and `CMPP`
- Updated `rtl/cu_top.sv`:
  - instantiates `id_stage` and `prf_top`
  - blocks illegal opcodes before issue
  - stops the GPU on fault and reports CSR fault code/PC
- Updated `rtl/lsu.sv`:
  - reports `MISALIGNED_ACCESS` for unsupported unaligned 32-bit LD/ST
  - reports `ADDRESS_ERROR` outside the current simulation memory window
- Updated `rtl/csr_regfile.sv` with status/fault CSRs.

## Software And Tests

- Updated `compiler/aec_assembler.py` to assemble `SETP/CMPP` with compare suffixes and predicate destinations.
- Updated PTX compiler guard encoding in `compiler/compiler.py` and root `compiler.py` so ordinary instructions no longer encode legacy `0xffff` as `pred_ctrl`.
- Added `tests/predicate_test.asm`.
- Added `tests/run_predicate_e2e.py`.
- Updated existing RTL e2e source lists to include `id_stage.sv` and `prf_top.sv`.
- Updated Python simulator negated predicate handling for execution and BRX.

## Local Validation

Passed:

- `python -m py_compile simulator.py tests/simulator.py compiler.py compiler/compiler.py compiler/aec_assembler.py tests/run_predicate_e2e.py tests/run_vector_add_e2e.py tests/run_alu_simt_e2e.py`
- Direct assembler assertions from `tests/test_assembler.py`
- `python tests/run_predicate_e2e.py --skip-xsim`
- `python tests/run_vector_add_e2e.py --skip-xsim`

Not run locally:

- XSim/Vivado RTL simulation. Local Windows environment has no `xvlog`, `xelab`, or `xsim`.

## Remote Vivado/XSim Validation

Remote environment:

- Host: `contest5@127.0.0.1:2222`
- Toolchain loaded with:
  - `source /apps/Xilinx2023/Vitis/2023.1/settings64.sh`
  - `source /opt/xilinx/xrt/setup.sh`
  - `source /opt/rh/devtoolset-9/enable`
  - `PLATFORM=xilinx_u280_gen3x16_xdma_1_202211_1`
- Vivado/XSim: 2023.1

Passed:

- `python3 tests/run_predicate_e2e.py`
  - `PREDICATE_E2E PASS`
  - lanes 0..3 wrote `A+B`
  - lanes 4..7 remained at sentinel values `0xdead0004..0xdead0007`
- `python3 tests/run_vector_add_e2e.py`
  - `VECTOR_ADD_E2E PASS`
- `python3 tests/run_alu_simt_e2e.py`
  - `ALU_SIMT_E2E PASS`
- `tb_lsu` standalone XSim:
  - `LSU TEST PASSED`
  - covers scatter/gather, masked lane skipping, and `MISALIGNED_ACCESS`
- `vivado -mode batch -source rtl/synth_cu_top_ooc.tcl`
  - `SYNTH_CU_TOP_OOC_PASS`
  - `0 Errors`, `0 Critical Warnings`
  - utilization summary: `LUT as Logic=6714`, `RAMB36E2=28`, `DSPs=24`

Artifacts:

- `reports/cu_top_ooc_utilization_stage7_4.rpt`
- `reports/cu_top_ooc_timing_stage7_4.rpt`
