# Stage 9.3 Multi-Warp Front-End and Per-Warp SIMT Stack

## Contract Basis

This pass targets the `contest.md` requirements that each CU must maintain
per-warp architectural state:

- warp PC
- active mask
- predicate state
- GPR state
- reconvergence stack
- correct multi-warp switching

The physical SIMD lanes remain an implementation detail; all masks and lane IDs
continue to describe the 32-lane logical warp.

## Implemented

- `rtl/warp_scheduler.sv`
  - Added `start_mask_i`.
  - Scheduler is now connected into `cu_top` for normal IMEM/CSR-driven execution.
  - Branch and HALT feedback update the selected warp's PC and active mask.

- `rtl/cu_top.sv`
  - Non-`USE_EXTERNAL_INSTR` mode now fetches through `warp_scheduler`.
  - The accepted instruction's `warp_id` and full logical active mask are latched
    with the issue state.
  - `warp_id` is propagated through IF/ID/issue/EX/WB/LSU and accelerator writeback.
  - `gpu_done` is driven by scheduler `all_warps_done` in normal mode.

- `rtl/ex_stage.sv`
  - Added `NUM_WARPS`, `issue_warp_i`, `ex_warp_o`, and `branch_warp_o`.
  - `simt_stack` is now instantiated as a per-warp stack array.
  - The internal BRX predicate mirror is now per-warp.

- `rtl/wb_stage.sv`, `rtl/lsu.sv`, `rtl/fpu_core.sv`,
  `rtl/warp_collective_core.sv`
  - Added warp tags so delayed writes return to the correct VRF/PRF warp slot.

- `rtl/tb_cu_multiwarp.sv`
  - New integrated test using CSR/AXI-Lite to write IMEM.
  - Runs `LOADI.u32 R1, 1; HALT` with two resident warps.
  - Checks that both warp0 and warp1 write their own VRF slot.

## Remote Validation

Remote XSim:

```text
CU_MULTIWARP TEST PASSED
FPU_EDGES TEST PASSED
FPU_COLLECTIVE TEST PASSED
WARP_STATE TEST PASSED
SCHEDULER_BARRIER TEST PASSED
PIPELINE TEST PASSED
```

Remote OOC synthesis:

```text
SYNTH_CU_TOP_OOC_PASS
0 errors, 0 critical warnings
```

Resource summary:

```text
CLB LUTs        82252  (6.31%)
CLB Registers   29046  (1.11%)
RAMB36E2           100  (4.96%)
DSPs                44  (0.49%)
URAM                 0
```

## Remaining Risks

- Multi-warp fetch is now live, but there is still no scoreboard. A later kernel
  with true register/data hazards across long-latency LSU/FPU/MMA paths needs
  dependency stalls or compiler scheduling.
- Dynamic `BAR.SYNC` is still validated standalone; it is not yet wired into
  `cu_top` issue stall/release.
- Predicated cross-beat `SHFL/REDUCE` still needs full predicate-mask collection.
- Full divergent BRX multi-warp end-to-end testing should be expanded beyond the
  existing unit/system smoke tests.
