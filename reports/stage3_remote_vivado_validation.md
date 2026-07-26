# Stage 3 Remote Vivado Validation

Date: 2026-07-26

## Connection

- Correct P2P endpoint: `127.0.0.1:2222`
- Login user: `contest5`
- Hostname: `localhost.localdomain`
- OS: CentOS Linux release 7.9.2009
- Kernel: `3.10.0-1160.108.1.el7.x86_64`
- Secondary P2P endpoint `127.0.0.1:2223` did not complete SSH banner negotiation during this check.

## Required Environment

The remote login shell does not expose Vivado/Vitis by default. Source the toolchain explicitly before simulation or synthesis:

```bash
source /apps/Xilinx2023/Vitis/2023.1/settings64.sh
source /opt/xilinx/xrt/setup.sh
source /opt/rh/devtoolset-9/enable
export PLATFORM=xilinx_u280_gen3x16_xdma_1_202211_1
```

Confirmed tools after sourcing:

- `xvlog`: `/apps/Xilinx2023/Vivado/2023.1/bin/xvlog`
- `xelab`: `/apps/Xilinx2023/Vivado/2023.1/bin/xelab`
- `xsim`: `/apps/Xilinx2023/Vivado/2023.1/bin/xsim`
- `vivado`: `/apps/Xilinx2023/Vivado/2023.1/bin/vivado`
- `v++`: `/apps/Xilinx2023/Vitis/2023.1/bin/v++`
- `xbutil`: `/opt/xilinx/xrt/bin/xbutil`
- `gcc`: `/opt/rh/devtoolset-9/root/usr/bin/gcc`

## Vivado Simulation

Command shape used:

```bash
cd /home/contest5/gpgpu_stage1/rtl
xvlog -sv aec_pkg.sv fetch_decode.sv issue_stage.sv vrf_lane.sv vrf_top.sv prf_top.sv cu_top.sv tb_cu_top.sv
xelab tb_cu_top -s tb_cu_top_sim
xsim tb_cu_top_sim -runall
```

Result:

```text
TEST PASSED
REMOTE_RC=0
```

Pipeline closure simulation:

```bash
cd /home/contest5/gpgpu_stage1/rtl
xvlog -sv aec_pkg.sv fetch_decode.sv issue_stage.sv vrf_lane.sv vrf_top.sv prf_top.sv alu_lane.sv ex_stage.sv wb_stage.sv cu_top.sv tb_cu_pipeline.sv
xelab tb_cu_pipeline -s tb_cu_pipeline_sim
xsim tb_cu_pipeline_sim -runall
```

Result:

```text
PIPELINE TEST PASSED
REMOTE_RC=0
```

This test seeds lane 0 VRF source registers, issues `IADD.u32 R1, R2, R3`, verifies active beats write back to R1, and verifies inactive lane/beat slots remain unchanged under the `32'hDEADBEEF` active mask.

LSU handshake simulation:

```bash
cd /home/contest5/gpgpu_stage1/rtl
xvlog -sv aec_pkg.sv lsu.sv tb_lsu.sv
xelab tb_lsu -s tb_lsu_sim
xsim tb_lsu_sim -runall
```

Result:

```text
LSU TEST PASSED
REMOTE_RC=0
```

This test delays `AWREADY`, `WREADY`, and `ARREADY`, then checks that the LSU holds AXI valid signals until handshake, generates lane-based `WSTRB`, packs store data into the low 256 bits of the 512-bit AXI data bus, and splits low 256-bit read data into eight 32-bit lane values.

Trace logger:

- Enabled only for simulation through ``ifndef SYNTHESIS``.
- File generated during `tb_cu_pipeline`: `trace_rtl.log`
- Observed writeback line format:

```text
[PC=0001] BEAT=0 MASK=ef REG[1] <- ...
```

## OOC Synthesis Smoke

VRF synthesis:

- Top: `vrf_top`
- Part: `xcu280-fsvh2892-2L-e`
- Result: `synth_design completed successfully`
- BRAM inference: `24 RAMB36E2`, matching 8 physical lanes x 3 replicated read banks
- Note: `rst_ni` is intentionally unused in `vrf_lane` to preserve a clean BRAM inference template.

PRF synthesis:

- Top: `prf_top`
- Part: `xcu280-fsvh2892-2L-e`
- Result: `synth_design completed successfully`
- BRAM/URAM usage: 0, matching the intended small FF/LUTRAM-style predicate file.

Integrated CU synthesis smoke:

- Top: `cu_top`
- Part: `xcu280-fsvh2892-2L-e`
- Result: `synth_design completed successfully`
- BRAM inference after EX/WB integration: `24 RAMB36E2`
- DSP inference: `24 DSPs`, from the placeholder scalar `IMUL.u32` lane multipliers
- Note: `cu_top` keeps the VRF instance with `keep_hierarchy/dont_touch` during this skeleton stage so the closed feedback loop is not optimized away before memory/trace outputs are added.
- LSU/Trace integration synthesis: `synth_design completed successfully`
- Resources after LSU/Trace integration include `24 RAMB36E2` and `24 DSP48E2`; Trace Logger is excluded from synthesis by `SYNTHESIS`.

## RTL Compatibility Fixes

- Module input ports now use `input wire logic ...` where needed so Vivado accepts the code under ``default_nettype none``.
- `prf_top.sv` function arguments remain `input logic ...`, which Vivado synthesis accepts.
- `alu_lane.sv`, `ex_stage.sv`, and `wb_stage.sv` were added to close the scalar MOV/IADD/IMUL execution and VRF writeback pipeline.
- `lsu.sv` and `trace_logger.sv` were added for Stage 3 memory bring-up and RTL trace diff.
