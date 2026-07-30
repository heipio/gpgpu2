# FPU/MMA Pipeline Timing Closure

Date: 2026-07-29

## Scope

This pass deep-pipelined the FP32 FMA-dependent datapaths and removed long
single-cycle numeric paths from the common EX/WB route while preserving the
AEC-G visible instruction semantics from `contest.md`.

## RTL Changes

- `rtl/fpu_core.sv`
  - Increased FP32 FMA latency to 8 cycles.
  - Added operand preparation stages before the Xilinx FP32 FMA IP.
  - Preserved `MAD.f32` as multiply-rounded then add-rounded, distinct from
    fused `FMA.f32`.

- `rtl/mma_core.sv`
  - Increased FP32 FMA latency to 8 cycles.
  - Added `MMA_COMPUTE_PREP` to register FP8 decoded operands and accumulator
    input before each FMA issue.
  - Preserved the required `k=0..15` accumulation order.

- `rtl/ex_stage.sv`
  - Added a registered calculation stage between VRF read capture and EX/WB
    outputs.
  - Removed SFU combinational results from the common EX result mux.

- `rtl/sfu_core.sv`
  - Added a fixed-latency SFU wrapper around existing `sfu_lane` RCP/EXP2
    logic.
  - SFU now writes through the accelerator VRF writeback path and is protected
    by scoreboard busy/clear.

- `rtl/cu_top.sv`
  - Connected `sfu_core` as an accelerator peer to FPU/MMA/collective cores.
  - Added SFU busy back-pressure to `issue_ready_eff`.
  - Added SFU writeback arbitration and scoreboard clear.

- `rtl/synth_cu_top_ooc.tcl`, `rtl/synth_soc_top_ooc.tcl`
  - Included `sfu_core.sv`.
  - Added 5 ns clocks for OOC timing.
  - Added an 8-cycle multicycle constraint for `u_sfu_core/src_q_reg` to
    `u_sfu_core/result_q_reg`, matching the SFU wait-state contract.

## Remote XSim Regression

Remote: `contest5@127.0.0.1:2222`

Environment:

```sh
source /apps/Xilinx2023/Vitis/2023.1/settings64.sh
source /opt/xilinx/xrt/setup.sh
source /opt/rh/devtoolset-9/enable
export PLATFORM=xilinx_u280_gen3x16_xdma_1_202211_1
```

Passed:

- `tb_soc_host_lifecycle`: `SOC_HOST_LIFECYCLE TEST PASSED`
- `tb_cu_scoreboard_barrier`: `CU_SCOREBOARD_BARRIER TEST PASSED`
- `tb_fpu_edges`: `FPU_EDGES TEST PASSED`
- `tb_fpu_collective`: `FPU_COLLECTIVE TEST PASSED`
- `tb_mma_core`: `MMA_CORE TEST PASSED`

## OOC Timing Evidence

CU OOC at 5.000 ns:

- Report: `reports/cu_top_ooc_timing_stage10_fpu_mma_sfu_multicycle.rpt`
- WNS: `+0.427 ns`
- TNS: `0.000 ns`
- Failing endpoints: `0`
- Worst setup path after closure:
  `u_imem/.../mem_reg_bram_3/CLKBWRCLK -> u_warp_scheduler/pc_q_reg[0][0]/CE`

SoC OOC at 5.000 ns:

- Report: `reports/soc_top_ooc_timing_stage10_fpu_mma_sfu_multicycle.rpt`
- WNS: `+0.339 ns`
- TNS: `0.000 ns`
- Failing endpoints: `0`
- Worst setup path after closure:
  `u_cu_top/u_imem/.../mem_reg_bram_3/CLKBWRCLK -> u_cu_top/u_scoreboard/pending_q_reg[0][0]/CE`

SoC utilization after this pass:

- CLB LUTs: `86,802`
- CLB Registers: `39,156`
- RAMB36E2: `100`
- DSP48E2: `44`
- URAM: `0`

## Remaining Signoff Notes

- These are Vivado 2023.1 OOC synthesis/timing results on the available remote
  environment. The contest-final evidence still needs Vivado/Vitis 2022.2 and
  routed timing on the U280 XDMA platform.
- The SFU multicycle path is architecturally valid because `sfu_core` holds
  `src_q` stable during `SFU_WAIT` and captures `result_q` only after the fixed
  latency expires. This constraint must be carried into the final constraints
  package.
- Current closure is OOC, not full placed/routed dynamic-region closure.
