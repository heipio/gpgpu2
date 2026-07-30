# Core Feature Completion Stage 9.1

Date: 2026-07-28

## Contract Scope Checked

Source of truth:

- `contest.md` sections 6.4.4, 6.4.8, 6.4.11, 6.4.12, 6.4.15
- `aec_g_isa_v1.json`

Key requirements used:

- `.f32 ADD/SUB/MUL/FMA` use IEEE-754 round-to-nearest-even.
- `MAD.f32` is not fused: multiply rounded to FP32, then add rounded to FP32.
- `SHFL` source lanes are logical lane IDs across the full 32-lane warp.
- `REDUCE` must collect the full active logical warp; inactive lanes are skipped without inserting identity values.
- Fault metadata must preserve code, PC, and CU/warp/block metadata.
- `BAR.SYNC expected_warps=0` means all live warps in the current block.

## RTL Implemented

- `rtl/fpu_core.sv`
  - 8 physical lanes, one Xilinx `aec_fp32_fma` wrapper per lane.
  - Supports `ADD.f32`, `SUB.f32`, `MUL.f32`, `FMA.f32`.
  - Supports `MAD.f32` using two rounded steps: multiply then add.
  - Writes VRF through the accelerator writeback path.

- `rtl/warp_collective_core.sv`
  - Collects `src1`/`src2` across all 4 issue beats, giving full 32 logical lane visibility.
  - Supports `SHFL` subops `IDX/XOR/UP/DOWN`.
  - Supports `REDUCE` subops `ADD/MAX/MIN/AND/OR/XOR` for integer/bitwise cases.
  - Supports `REDUCE.ADD.f32` with a balanced tree and FMA-wrapper FP32 additions.
  - Skips inactive lanes without injecting identity values.

- `rtl/cu_top.sv`
  - Added multi-cycle stall integration for MMA, FPU, and collective units.
  - Added common accelerator VRF read/write arbitration.
  - Added trace mux for accelerator writeback.
  - Added watchdog counter and `WATCHDOG_TIMEOUT` fault path.

- `rtl/wb_stage.sv` / `rtl/ex_stage.sv`
  - Added type propagation so `.u32` ALU and `.f32` FPU instructions sharing opcodes are separated correctly.
  - Suppresses normal WB for FPU and collective instructions; their result is written by the multi-cycle engines.

- `rtl/csr_regfile.sv` / `rtl/aec_pkg.sv`
  - Added `CSR_FAULT_META` at `0x0014`.

- `rtl/warp_scheduler.sv`
  - Synthesizable round-robin multi-warp PC/active-mask scheduler skeleton.

- `rtl/barrier_unit.sv`
  - Synthesizable dynamic barrier accounting skeleton supporting `expected_warps=0`.

- `rtl/tb_fpu_collective.sv`
  - Standalone unit test for FPU FMA, cross-beat `SHFL.XOR`, and `REDUCE.ADD.f32`.

- `rtl/tb_cu_pipeline.sv`
  - Fixed stale official opcode encoding for `ADD.u32` after contract opcode correction.

## Remote Validation

Remote:

```text
contest5@127.0.0.1:2222
/home/contest5/gpgpu_stage9_base
Vivado/Vitis 2023.1
```

Tests:

```text
tb_fpu_collective: FPU_COLLECTIVE TEST PASSED
tb_cu_pipeline:   PIPELINE TEST PASSED
```

Full RTL analysis:

```text
xvlog completed for CU + FPU + collective + scheduler/barrier modules
```

OOC synthesis:

```text
SYNTH_CU_TOP_OOC_PASS
0 Errors, 0 Critical Warnings
```

Resource summary:

```text
CLB LUTs        79274  (6.08%)
CLB Registers   27291  (1.05%)
RAMB36E2            28
DSPs                44  (0.49%)
URAM                 0
aec_fp32_fma IP instances: 10
```

## Remaining Correctness Gaps

- `warp_scheduler.sv` and `barrier_unit.sv` are not yet integrated into the active `cu_top` fetch path. Current `cu_top` remains a single-warp execution path with multi-cycle FPU/MMA/collective engines.
- Fully correct predicated `SHFL/REDUCE` needs PRF cross-beat collection. The current collective engine uses the logical active mask but does not yet collect predicate masks for all 32 lanes.
- True multi-warp/block execution requires VRF/PRF state partitioning or banking by warp ID before the scheduler can safely replace the current single-warp front end.
- OOC timing still lacks top-level U280 clock-buffer context; final timing must be checked under platform constraints.
