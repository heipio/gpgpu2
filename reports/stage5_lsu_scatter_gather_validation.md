# Stage 5 LSU Scatter/Gather Validation

Date: 2026-07-26

## Scope

Stage 5 replaces the lane0-only 256-bit LSU behavior with a true per-lane scatter/gather engine.

## RTL Changes

- `rtl/lsu.sv`
  - Adds a lane iteration state machine:
    - `LSU_IDLE`
    - `LSU_NEXT_LANE`
    - `LSU_STORE_ADDR_DATA`
    - `LSU_STORE_RESP`
    - `LSU_LOAD_ADDR`
    - `LSU_LOAD_DATA`
    - `LSU_DONE`
  - Captures the full 8-lane EX payload at LSU start.
  - Iterates `lane_idx_q` from 0 to 7.
  - Skips inactive lanes without issuing AXI transactions.
  - Computes each active lane address independently:
    - `lane_addr = src1_data[lane] + src2_data[lane]`
  - Issues one 32-bit AXI transfer per active lane:
    - `awsize = 3'd2`
    - `arsize = 3'd2`
  - Uses the 512-bit AXI data bus as a narrow-access beat:
    - AXI beat address is 64-byte aligned.
    - `addr[5:0]` selects the byte lane inside `wdata/wstrb` and `rdata`.
  - For LD, gathers each returned 32-bit lane value into `load_data_q[lane]`.
  - Asserts `load_valid_o` only after all active lanes have completed.

## Testbench Changes

- `rtl/tb_lsu.sv`
  - Adds scatter store with 8 non-contiguous addresses:
    - `0x1000, 0x2004, 0x3008, ...`
  - Verifies 8 independent write transactions.
  - Adds gather load with 8 non-contiguous addresses and checks all lane results.
  - Adds masked store test with active mask `8'b1010_0101`, checking only active lanes write memory.
  - Checks `awsize/arsize == 3'd2`.

- `rtl/tb_divergent_brx_system.sv`
  - Updates lane1 store base to `0x3004`.
  - This matches Stage 5 semantics: each active lane now uses its own explicit address instead of relying on lane position inside a wide store.

## Remote Validation

Remote path:

```text
/home/contest5/gpgpu_stage5/rtl
```

Vivado/Vitis used for local validation:

```text
Vivado/Vitis 2023.1
Target part: xcu280-fsvh2892-2L-e
```

Note: final contest evidence still needs the official 2022.2 flow.

## XSim Regression

All tests passed:

```text
tb_cu_top                 : TEST PASSED
tb_cu_pipeline            : PIPELINE TEST PASSED
tb_lsu                    : LSU TEST PASSED
tb_system                 : [SYSTEM TEST] PASS
tb_loop_system            : [LOOP TEST] PASS
tb_divergent_brx_system   : [DIVERGENT BRX TEST] PASS
```

## OOC Synthesis

Command:

```bash
vivado -mode batch -source synth_stage5_ooc.tcl
```

Result:

```text
synth_design completed successfully
0 errors
0 critical warnings
```

Representative resource summary:

```text
RAMB36E2 : 24
DSP48E2  : 24
FDCE     : 1742
LUT6     : 1324
MUXF7    : 290
MUXF8    : 64
```

The LSU grew, as expected, because it now contains lane iteration, address alignment, byte-lane selection, and gather buffering.

## Readiness Verdict

Stage 5 LSU scatter/gather is complete for 8-lane, 32-bit LD/ST semantics. The implementation now respects per-lane addresses and inactive-lane silence, and the existing CU control-flow/system tests continue to pass.

Remaining risks:

- Misaligned 32-bit accesses are currently byte-lane shifted if they fit inside one 512-bit beat; architectural `MISALIGNED_ACCESS` fault policy still needs to be finalized.
- Cross-64-byte 32-bit accesses are not split; compiler/runtime should avoid them or RTL should fault/split them in the next memory-safety pass.
- AXI response errors are consumed but not yet reported through architectural fault/status registers.
