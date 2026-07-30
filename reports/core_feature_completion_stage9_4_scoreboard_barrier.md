# Stage 9.4 Scoreboard and Barrier Completion

Date: 2026-07-28

## Contract Points

- Scoreboard is per warp and tracks pending GPR destinations before issue, preventing RAW and WAW hazards from reading or overwriting in-flight results.
- Pending GPR state is cleared only when the full 4-beat warp instruction has reached writeback, or when a multi-cycle accelerator writes its destination register.
- Dynamic `BAR.SYNC` uses the scheduler's live-warp mask. `expected_warps == 0` means all currently live warps in the block.
- A warp that reaches a barrier is removed from scheduler eligibility until the barrier releases. Released warps keep their already advanced PC and resume after the barrier instruction.
- Barrier deadlock is mapped to `AEC_FAULT_BARRIER_DEADLOCK` with the barrier id in `fault_meta[2:0]`.

## Implemented RTL

- Added `rtl/scoreboard.sv`
  - Per-warp 256-bit pending GPR bitmap.
  - RAW checks for source operands.
  - WAW check for destination operands.
  - Immediate source-2 operands do not create false register hazards.

- Updated `rtl/warp_scheduler.sv`
  - Added `warp_stall_mask_i`.
  - Added `live_warps_o`.
  - Round-robin selection skips barrier-stalled warps.

- Updated `rtl/cu_top.sv`
  - Instantiated scoreboard in the decode/issue accept path.
  - Instantiated `barrier_unit` in the real EX/scheduler path.
  - Added barrier stall state and release handling.
  - Added barrier-deadlock fault propagation to CSR fault reporting.

- Updated `rtl/ex_stage.sv`
  - Exposed `ex_src2_imm_o` so `BAR.SYNC id,count` can use the decoded expected-warp count.

- Updated synthesis file
  - Added `scoreboard.sv` to `rtl/synth_cu_top_ooc.tcl`.

## New Tests

- `rtl/tb_scoreboard.sv`
  - Verifies RAW src1 hazard.
  - Verifies WAW dst hazard.
  - Verifies hazard clear.
  - Verifies immediate src2 does not false-trigger.

- `rtl/tb_cu_scoreboard_barrier.sv`
  - Runs a 2-warp kernel through `cu_top`.
  - Exercises ALU dependency around scoreboard path.
  - Executes `BAR.SYNC 0,0`.
  - Verifies both warps resume after dynamic barrier release and produce expected register results.

## Remote Validation

Environment:

```text
host: contest5@127.0.0.1:2222
workdir: /home/contest5/gpgpu_stage9_base/rtl
Vivado/Vitis: 2023.1
XRT setup: /opt/xilinx/xrt/setup.sh
PLATFORM: xilinx_u280_gen3x16_xdma_1_202211_1
```

Passed XSim tests:

```text
SCOREBOARD TEST PASSED
CU_SCOREBOARD_BARRIER TEST PASSED
CU_MULTIWARP TEST PASSED
SCHEDULER_BARRIER TEST PASSED
```

Vivado OOC synthesis:

```text
SYNTH_CU_TOP_OOC_PASS
Synthesis finished with 0 errors, 0 critical warnings and 341 warnings.
```

Resource summary after Stage 9.4:

```text
CLB LUTs      85221 / 1303680 = 6.54%
CLB Registers 30069 / 2607360 = 1.15%
RAMB36E2      100
DSPs          44 / 9024 = 0.49%
```

Pulled reports:

- `reports/cu_top_ooc_utilization_stage9_4_scoreboard_barrier.rpt`
- `reports/cu_top_ooc_timing_stage9_4_scoreboard_barrier.rpt`

## Remaining Risks

- The scoreboard is conservative at register granularity. It is correct for scalar/LD/ST/SFU/FPU single-destination instructions and safe for accelerator writeback, but MMA fragment-level dependency tracking should be expanded from base-register tracking to full fragment range tracking before heavy MMA kernels.
- The current barrier implementation covers per-block live-warp synchronization in the single-CU skeleton. Multi-block scheduling and barrier namespace isolation still need to be added before full contest closure.
- Timing summary is OOC without full platform clocks/floorplan constraints. Final routed U280 timing remains required.
