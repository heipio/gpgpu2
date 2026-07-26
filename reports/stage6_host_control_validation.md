# Stage 6 Host Control Validation

Date: 2026-07-26

## Implemented

- Added `rtl/csr_regfile.sv` with an AXI4-Lite slave CSR block.
- Implemented CSR map:
  - `0x0000 CSR_CTRL`: bit 0 START pulse, bit 1 DONE status / write-one-clear.
  - `0x0004 CSR_PC`: kernel start PC.
  - `0x1000..0x1fff IMEM_WINDOW`: 32-bit instruction word writes into 128-bit IMEM entries.
- Updated `rtl/imem.sv` into a synchronous dual-port RAM model:
  - Port A: AXI-Lite 32-bit instruction loading and optional 32-bit readback.
  - Port B: 128-bit instruction fetch.
  - Little-endian word placement: `0x1000 + pc*16 + 0` maps to instruction `[31:0]`; `+12` maps to `[127:96]`.
- Updated `rtl/if_stage.sv` with START PC loading and run-enable gating.
- Updated `rtl/cu_top.sv`:
  - Removed dummy AXI-Lite responses.
  - Instantiated `csr_regfile`.
  - Connected CSR-driven IMEM writes.
  - Added GPU running state and HALT-to-DONE feedback.
- Updated `rtl/ex_stage.sv` so `LD/ST` use the instruction `src2` field as a 32-bit immediate offset into LSU address calculation.
- Reworked `rtl/tb_system.sv`:
  - No `$readmemh` dependency for the tested program.
  - No hierarchical IMEM writes.
  - No VRF backdoor register seeding.
  - Host writes parameters and data to the AXI memory model, loads machine code through AXI-Lite, starts the CU, polls DONE, and checks the memory result.

## Remote XSim

Remote path: `/home/contest5/gpgpu_stage6/rtl`

Command sequence:

```sh
source /apps/Xilinx2023/Vitis/2023.1/settings64.sh
xvlog -sv aec_pkg.sv alu_lane.sv csr_regfile.sv fetch_decode.sv issue_stage.sv vrf_lane.sv vrf_top.sv simt_stack.sv ex_stage.sv lsu.sv wb_stage.sv trace_logger.sv imem.sv if_stage.sv cu_top.sv tb_system.sv
xelab tb_system -s tb_system_sim
xsim tb_system_sim -runall
```

Result:

```text
[SYSTEM TEST] PASS
```

## Remote OOC Synthesis

Tool: Vivado 2023.1 on CentOS 7.9, U280 part `xcu280-fsvh2892-2L-e`.

Result:

```text
synth_design completed successfully
Synthesis finished with 0 errors, 0 critical warnings
```

Representative utilization after Stage 6:

```text
RAMB36E2 = 24
DSP48E2  = 24
```

## Known Risk

Vivado 2023.1 OOC synthesis still maps the current IMEM model to LUTRAM despite `ram_style = "block"`:

```text
Infeasible attribute ram_style = "block" set for RAM "u_imem/mem_reg", trying to implement using LUTRAM
u_imem/mem_reg: 256 x 128, RAM256X1D based LUTRAM
```

This does not block Stage 6 functional bring-up, but it should be fixed before scaling instruction memory. The next hardening step should replace inferred IMEM with an explicit Xilinx XPM/BRAM wrapper or a RAMB36E2-based module while keeping the same CSR/IF contract.

## Compatibility Note

This validation used the available remote Vivado 2023.1 installation. The official contest contract still requires final compatibility evidence on Vivado/Vitis 2022.2.
