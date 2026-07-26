# Full Contract Audit - 2026-07-26

Official source: `contest.md`

## Status

Current mode: implementation/debug.

The project now has coherent Stage 1 through Stage 9 base infrastructure, but it is not yet a complete contest submission. The main score-blocking gaps are the unfinished full FP8 MMA RTL integration, official U280 xclbin/bitstream, XDMA board runtime, and model-level PyTorch/ResNet/LLM paths.

## Critical Issues Found And Fixed

1. Official opcode mismatch.
   - Problem: early files used private/old opcodes such as `NOP=0x0000`, `LD=0x0010`, `BR=0x0020`, `SFU.RCP=0x0040`, `HALT=0x007f`.
   - Official `contest.md` 6.4.6/6.4.14 requires `ADD=0x0001`, `LD=0x0030`, `BR=0x0040`, `CPY=0x0054`, `MMA=0x0070`, `SFU=0x0080`, `NOP=0x00f0`.
   - Fixed in `aec_g_isa_v1.json`, `rtl/aec_pkg.sv`, `compiler/aec_assembler.py`, `compiler/compiler.py`, root `compiler.py`, `tests/simulator.py`, root `simulator.py`, and `tests/test_contract_audit.py`.

2. `pred_ctrl` bit layout mismatch.
   - Problem: early implementation used `pred_neg=bit3`, `type=bits7:4`, `imm_en=bit8`, `space=bits10:8`, `ctrl=bits14:12`.
   - Official `contest.md` 6.4.3 requires `pred[2:0]`, `type[6:3]`, `imm_en[7]`, `subop[10:8]`, `space[13:11]`, `pred_neg[14]`, `pred_en[15]`.
   - Fixed in JSON, assembler, compiler guard/memory/type encoding, RTL fetch decode, EX immediate selection, and contract tests.

3. SFU opcode/subop contract mismatch.
   - Problem: SFU RCP/EXP2 were split into two opcodes.
   - Official requires unified opcode `0x0080`; `subop=0` is RCP and `subop=1` is EXP2.
   - Fixed in `rtl/sfu.sv`, `rtl/ex_stage.sv`, `rtl/id_stage.sv`, `rtl/wb_stage.sv`, compiler, assembler, simulator, and Stage 8 report.

4. Generated `.hex/.aecbin` artifacts were stale.
   - Regenerated `tests/vector_add.*`, `tests/alu_simt.*`, `tests/predicate_test.*`, and `tests/sfu_test.*` with the corrected assembler.

## Verified After Fix

Local:

- `python -m json.tool aec_g_isa_v1.json`
- `python tests/test_contract_audit.py`
- `python tests/test_sim.py`
- `python tests/test_compiler.py`
- `python tests/test_assembler.py`
- `python tests/sfu_model_sweep.py --samples 20000`
- `python tests/mma_model.py -o tests/mma_vectors.json`
- `python skills/u280-gpgpu-contest-completer/scripts/audit_submission.py .`

Remote Vivado 2023.1 development environment:

- `python3 tests/test_contract_audit.py`
- `python3 tests/test_sim.py`
- `python3 tests/test_compiler.py`
- `xvlog -sv aec_pkg.sv fetch_decode.sv id_stage.sv alu_lane.sv simt_stack.sv sfu.sv ex_stage.sv wb_stage.sv`

Previous still-valid remote checks:

- `FP8_DECODER TEST PASSED`
- `FP32_FMA_IP_WRAP TEST PASSED`

## Completed Work By Stage

- Stage 1: ISA JSON and Python golden simulator exist; FP8 E4M3FN conversion, SFU model, reduction skip semantics, SIMT control helpers, and tests are present.
- Stage 2: PTX-to-AEC compiler skeleton, assembler, runtime C API skeleton, Python simulation runtime, and PyTorch adapter skeleton exist.
- Stage 3: CU RTL skeleton, fetch/decode, issue beats, VRF/PRF, ALU, EX/WB, LSU, trace logger, and base testbenches exist.
- Stage 4: IMEM/IF stage and host-driven simulation flow exist.
- Stage 4.2: SIMT stack, BRX/SSY/SYNC branch path and divergent BRX tests exist.
- Stage 5: LSU scatter/gather state machine exists for 32-bit lane-wise AXI transactions.
- Stage 6/6.1: AXI-Lite CSR host control and XPM IMEM path exist.
- Stage 7: assembler, Python runtime command protocol, SIMT `%laneid`, predicate/fault CSR pieces, and contract audit tests exist.
- Stage 8: SFU RCP/EXP2 model sweep and RTL approximation path exist, now corrected to official SFU opcode/subop encoding.
- Stage 9 base: official MMA opcode/layout is recorded, FP8 decoder exists, Python MMA golden model/test vectors exist, and Xilinx Floating-Point FMA IP wrapper plus generated XCI are validated.

## Remaining Score-Blocking Work

1. Full MMA RTL is not complete.
   - Need `mma_core.sv` with official 6.4.13 lane/register layout.
   - Need strict `k=0..15` FP32 FMA accumulation order.
   - Need multi-cycle issue stall, scoreboard/writeback, and illegal partial-warp MMA fault.
   - Need XSim comparison against `tests/mma_vectors.json`.

2. Official typed ALU/FPU semantics are incomplete.
   - Official ADD/MUL use one opcode with type field; current RTL integer ADD/MUL path works, but full `.f32` ADD/MUL and exact MAD/FMA semantics are not implemented in the CU datapath.

3. Cross-beat SHFL/REDUCE RTL remains incomplete.
   - Golden simulator has reduction semantics, but RTL needs a warp-level cross-beat buffer/replay path for `PHYSICAL_SIMD_LANES=8`.

4. Multi-warp/block features remain incomplete.
   - Current CU is essentially single-warp bring-up.
   - Need resident warp scheduling, dynamic `BAR.SYNC expected_warps=0`, block completion, watchdog, and richer fault metadata.

5. Runtime/driver is not board-scoreable yet.
   - C API skeleton exists, but XDMA BAR/MMIO/DMA integration, capability probing, manifest validation, async queues, counters, and 64-bit pointer window tables need production implementation.

6. U280 platform deliverables are missing.
   - No final routed xclbin/bitstream.
   - `constraints/`, `platform/`, `driver/`, `bitstream/` are present for structure but not complete scoreable artifacts.
   - Need official Vivado/Vitis 2022.2-compatible build path or documented validated compatibility.

7. PyTorch/model scoring path is only a skeleton.
   - Need P0/P1 operators through runtime without scoreable CPU fallback.
   - Need ResNet-18/ResNet-50 and approximately 1B Transformer scheduling, quantization, fallback logs, state reset, KV cache handling, on-device argmax, and EOS fill behavior.

8. Final evidence is missing.
   - Need routed timing with WNS >= 0, utilization/power/thermal logs, 30-minute stability, board correctness logs, benchmark raw data, third-party IP list, reproducibility commands, and final `design.json` review.
