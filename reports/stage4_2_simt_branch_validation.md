# Stage 4.2 SIMT Branch Validation

Date: 2026-07-26

## Scope

Stage 4.2 adds the first SIMT control-flow path:

- Reconvergence token stack
- Predicate generation through `SETP`
- Uniform and predicate branch handling through `BRA` and `BRX`
- `SSY`/`SYNC` push/pop hooks
- IF redirect and one-cycle flush on branch redirect
- Active-mask maintenance in `cu_top`
- End-to-end loop test

## RTL Added Or Updated

- `rtl/simt_stack.sv`
  - Depth-8 stack for `{pc, active_mask}` reconvergence tokens.
  - Synchronous push/pop control.
  - Reports overflow/underflow for future fault plumbing.

- `rtl/ex_stage.sv`
  - Adds predicate mask state: 8 predicate registers, each represented as a 32-bit logical-lane mask.
  - `SETP` updates predicate bits for the current 8-lane beat.
  - `BRA` redirects PC on beat 0.
  - `BRX` follows the golden simulator rule:
    - compute `taken_mask` and `fallthrough_mask` from current active mask and predicate mask
    - if both masks are non-zero, push `{fallthrough_pc, fallthrough_mask}` and branch to target under `taken_mask`
    - if only taken exists, branch to target
    - if only fallthrough exists, continue at `pc + 1`
  - `SSY` pushes `{reconv_pc, current_active_mask}`.
  - `SYNC` pops `{pc, mask}` and redirects.

- `rtl/if_stage.sv`
  - Adds `branch_taken_i`, `branch_target_i`, and `flush_i`.
  - Branch redirect has priority over sequential PC increment.

- `rtl/cu_top.sv`
  - Maintains `current_active_mask_q`.
  - Synchronizes initial active mask after reset, before accepting IF/ID traffic.
  - Flushes IF/ID valid on branch redirect.
  - Passes branch metadata between IF, issue, and EX.

- `rtl/tb_loop_system.sv`
  - End-to-end loop program:
    - `sum = 0`
    - `i = 0`
    - loop while `i != 4`
    - `sum += i`
    - `i += 1`
    - store result to `0x3000`
  - Expected result: `6`.

- `rtl/tb_divergent_brx_system.sv`
  - Directed divergent branch test with initial active mask `0x00000003`.
  - Lane 0 predicate is true, lane 1 predicate is false.
  - Verifies `BRX` redirects to taken path under mask `0x1`, first `SYNC` pops fallthrough PC under mask `0x2`, and second `SYNC` pops final reconvergence PC under mask `0x3`.
  - Stores lane 0 result `100` at `0x3000` and lane 1 result `200` at `0x3004`.

## Remote Validation

Remote path:

```text
/home/contest5/gpgpu_stage42/rtl
```

Vivado/Vitis used for this local validation:

```text
Vivado/Vitis 2023.1
Target part: xcu280-fsvh2892-2L-e
```

Note: the final contest environment still needs official 2022.2 compatibility evidence.

## XSim Results

All regression tests passed:

```text
tb_cu_top       : TEST PASSED
tb_cu_pipeline  : PIPELINE TEST PASSED
tb_lsu          : LSU TEST PASSED
tb_system       : [SYSTEM TEST] PASS
tb_loop_system  : [LOOP TEST] PASS
tb_divergent_brx_system : [DIVERGENT BRX TEST] PASS
```

The loop trace showed `R3` accumulating through the expected sequence and ending at `0x00000006`.
The divergent BRX test confirmed that taken and fallthrough masks were both non-zero and that `SYNC` restored the fallthrough and final reconvergence masks in order.

## OOC Synthesis

Command:

```bash
vivado -mode batch -source synth_stage42_ooc.tcl
```

Result:

```text
synth_design completed successfully
0 errors
0 critical warnings
```

Representative post-synthesis resources:

```text
RAMB36E2 : 24
DSP48E2  : 24
FDCE     : 963
CARRY8   : 52
```

Expected residual warnings:

- `instr_ready_o` is constant zero in the default internal-IMEM mode.
- LSU currently consumes lane 0 address lanes only, so Vivado reports unused high-lane address inputs.
- OOC timing is still unconstrained, so timing summary is not final timing closure evidence.

## Readiness Verdict

Stage 4.2 is complete for the baseline single-warp control-flow bring-up. The CU can now execute simple loops and conditional branch sequences with active-mask updates and IF redirect/flush.

Remaining RTL risks before broader SIMT correctness:

- Connect `simt_stack_fault_o` into architectural fault/status registers.
- Add a dedicated predicate register file integration path or align the existing internal EX predicate masks with the final PRF contract.
- Improve trace PC tagging by carrying instruction PC down to WB.
