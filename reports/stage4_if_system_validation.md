# Stage 4 IF/System Validation

Date: 2026-07-26

## Scope

Stage 4 first-step bring-up adds a real instruction-fetch front end and verifies a `VECTOR_ADD_PTX`-style end-to-end loop through:

- IMEM instruction ROM: `imem.sv`
- IF stage PC and handshake: `if_stage.sv`
- CU integration: `cu_top.sv`
- System-level AXI memory model and vector-add test: `tb_system.sv`
- Test program: `inst.hex`

## RTL Added Or Updated

- `rtl/imem.sv`: 128-bit instruction memory, 1024 entries, initialized by `$readmemh("inst.hex", mem)`.
- `rtl/if_stage.sv`: PC reset to zero, `imem_addr_o = pc_q`, handshake-driven PC increment.
- `rtl/cu_top.sv`: default path now uses `imem -> if_stage -> fetch_decode`; external instruction path is retained with `USE_EXTERNAL_INSTR=1` for legacy unit tests.
- `rtl/tb_system.sv`: instantiates `cu_top`, models AXI4-MM memory, backdoor-initializes lane-0 VRF base registers, runs LD/LD/IADD/ST/HALT.
- `rtl/inst.hex`: program sequence:
  - `LD R4, [R0 + R31]`
  - `LD R5, [R1 + R31]`
  - `IADD R6, R4, R5`
  - `ST [R2 + R31], R6`
  - `HALT`

## Remote Environment

- Remote path: `/home/contest5/gpgpu_stage4/rtl`
- Vivado/Vitis used for local board validation: `2023.1`
- Target part for OOC synthesis: `xcu280-fsvh2892-2L-e`
- Note: contest contract still requires final compatibility evidence against the official 2022.2 flow; 2023.1 is local validation evidence only.

## XSim Regression

Command class:

```bash
xvlog -sv aec_pkg.sv fetch_decode.sv if_stage.sv imem.sv issue_stage.sv vrf_lane.sv vrf_top.sv prf_top.sv alu_lane.sv ex_stage.sv wb_stage.sv lsu.sv trace_logger.sv cu_top.sv tb_cu_top.sv tb_cu_pipeline.sv tb_lsu.sv tb_system.sv
xelab <tb> -s <snapshot>
xsim <snapshot> -runall
```

Results:

- `tb_cu_top`: `TEST PASSED`
- `tb_cu_pipeline`: `PIPELINE TEST PASSED`
- `tb_lsu`: `LSU TEST PASSED`
- `tb_system`: `[SYSTEM TEST] PASS`

System trace evidence:

```text
[PC=0001] BEAT=0 MASK=01 REG[4] <- ... 0000007b
[PC=0002] BEAT=0 MASK=01 REG[5] <- ... 000001c8
[PC=0003] BEAT=0 MASK=01 REG[6] <- ... 00000243
```

The test memory check confirms address `0x3000` receives decimal `579` (`0x243`), matching `123 + 456`.

## Vivado OOC Synthesis

Command:

```bash
vivado -mode batch -source synth_stage4_ooc.tcl
```

Result:

- `synth_design completed successfully`
- Errors: `0`
- Critical warnings: `0`
- Representative utilization after synthesis:
  - `RAMB36E2`: `24`
  - `DSP48E2`: `24`
  - `FDCE`: `930`
  - `CARRY8`: `53`

Important warnings:

- `instr_ready_o` is constant `0` when the default internal-IMEM fetch path is selected; this is intentional because the external instruction stream is disabled unless `USE_EXTERNAL_INSTR=1`.
- OOC timing has no real clock constraint yet, so WNS/TNS are `NA`. Stage 4 only proves synthesizability, not timing closure.
- IMEM is initialized from `inst.hex` in synthesis. For final runtime-loaded kernels, IMEM will need a loader/write path or instruction DMA instead of a fixed simulation ROM.

## Readiness Verdict

Stage 4 first-step IF front end and `VECTOR_ADD_PTX` end-to-end RTL simulation loop are complete. The current CU can fetch from IMEM, decode, issue four beats, read VRF, execute LD/LD/IADD/ST, write back, log trace, and halt under XSim.

Next RTL risk items before full kernel bring-up:

- Replace fixed `inst.hex` ROM with runtime-loadable instruction memory.
- Add real clock constraints and repeat timing-oriented synthesis.
- Extend LSU beyond lane-0 base addressing toward vector/scatter-gather semantics.
- Add fault/status reporting for illegal instruction, misalignment, and AXI response errors.
