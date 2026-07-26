# Full Project Audit

Date: 2026-07-26

## Current Position

The project is at the end of Stage 7.3: scalar/SIMT infrastructure bring-up is
working in RTL simulation. The current system can assemble/load/launch small
AEC kernels through the Python simulation runtime, execute scalar ALU and
scatter/gather memory operations on 8 physical lanes, and validate results via
XSim. This is not yet a complete contest submission.

Mode classification: implementation.

## Verified Working Surface

- Machine-readable ISA exists in `aec_g_isa_v1.json`.
- Golden simulator covers FP8 E4M3FN conversion, SFU numeric reference
  functions, MMA golden accumulation order, SIMT stack unit tests, and current
  Stage 7 scalar ALU semantics.
- Assembler emits strict headerless 128-bit `.aecbin`.
- PTX compiler parses and lowers a restricted subset, including b128 lowering,
  b64/MMA register-alignment diagnostics, scalar ALU, LD/ST, SETP, branch,
  SFU, and MMA opcode emission.
- Contract guard test checks opcode, special register, and memory-space encoding
  consistency across JSON, assembler, PTX compiler, simulator, and RTL.
- RTL currently includes:
  - `imem` XPM BRAM instruction memory.
  - IF/fetch-decode/issue.
  - 8-lane VRF and small PRF.
  - scalar ALU for MOV/IADD/IMUL/SUB/AND/OR/XOR/SHL/SHR.
  - `%laneid` special register as logical lane id.
  - BRX/SSY/SYNC SIMT stack bring-up.
  - vector LSU scatter/gather over per-lane 32-bit AXI transfers.
  - CSR/AXI-Lite host start/done and IMEM loading.
  - trace logger for simulation.
- Remote Vivado/XSim 2023.1 validation has passed for vector-add and 8-lane
  SIMT ALU E2E tests.

## Tests Re-run During This Audit

```text
python skills/u280-gpgpu-contest-completer/scripts/audit_submission.py .
python tests/test_contract_audit.py
python tests/test_compiler.py
python tests/test_sim.py
python tests/test_sim_ctrl.py
python tests/test_differential.py
python tests/test_assembler.py
python tests/run_vector_add_e2e.py --skip-xsim
python tests/run_alu_simt_e2e.py --skip-xsim
```

Official-style repository audit result:

```text
[MISSING] bitstream/xclbin artifact
[MISSING] timing/util/power/benchmark reports
```

## Serious Gaps / Vulnerabilities

1. No FP8/MMA/SFU RTL yet.
   - `alu_lane.sv` returns zero for FADD/FMUL/MAD/FMA placeholders.
   - RTL has opcode constants for SFU/MMA but no executable SFU/MMA units.
   - Contest numerical gates for FP8 MMA, SFU RCP, and SFU EXP2 are therefore
     only golden-model gates today, not hardware gates.

2. Predicate semantics are incomplete in RTL.
   - `pred_ctrl` is decoded, and BRX uses predicate masks, but general
     predicated ALU/LD/ST write suppression is not yet fully applied.
   - Hidden predication tests can still expose inactive/predicate-masked writes.

3. Fault/status reporting is not architecturally wired.
   - SIMT stack overflow/underflow exists internally but is not exposed through
     CSR/status/fault registers.
   - Illegal instruction, unsupported type/space, misaligned access, AXI
     response errors, address errors, watchdog, and barrier deadlock are not a
     complete hardware-visible fault system.

4. Memory correctness is still bring-up level.
   - LSU handles per-lane 32-bit scatter/gather but does not implement b8/b16/b64
     widening/narrowing, even-register-pair writeback, atomics, coalescing, or
     cross-64-byte split/fault behavior.
   - Runtime 64-bit pointer windowing exists as a host skeleton, but RTL does
     not consume a real address-window table from host.
   - FENCE/cache flush/invalidate policy is not implemented beyond comments and
     stage documentation.

5. Host/runtime is not XDMA-backed.
   - `runtime/aec_runtime.cpp` is a host-shadow skeleton with TODOs for XDMA
     command queue submission, completion polling, and cache consistency.
   - `runtime/aec_runtime_sim.py` is useful for XSim but is not the board
     runtime.

6. PyTorch path is not scoreable.
   - `pytorch/aec_torch.py` blocks scoreable CPU fallback correctly, but real
     FPGA-backed P0/P1 operators are not implemented.
   - FP8 GEMM, add/mul/relu, Conv2d, residual, pooling, LayerNorm, Softmax,
     attention, KV cache, and on-device argmax remain future work.

7. No Vitis/XDMA platform integration yet.
   - `constraints/`, `platform/`, `driver/`, and `bitstream/` are placeholders.
   - No `connectivity.cfg`, HBM port mapping, kernel wrapper, xclbin build, or
     board programming flow exists.

8. No PPA or board evidence.
   - Only OOC/bring-up synthesis evidence exists for early RTL, including XPM
     IMEM BRAM inference.
   - No routed timing closure, WNS, utilization per SLR, power, thermal,
     bandwidth, long-run stability, or benchmark logs are present.

9. Model scoring workloads are not implemented.
   - No ResNet-18/ResNet-50 end-to-end path.
   - No approximately 1B decoder-only Transformer path.
   - No accuracy gates, token generation, EOS padding, perplexity/token-match
     validation, or model benchmark harness.

10. Repository hygiene risk remains.
   - Root-level compatibility mirrors (`compiler.py`, `simulator.py`, tests) and
     directory versions are currently synchronized, but this is fragile.
   - Long term, root files should become thin wrappers or be removed if the
     submission harness permits.

## Recommended Next Stages

1. Stage 7.4: complete predicated execution and architectural fault/status CSR.
   This should happen before MMA/SFU to prevent masked-lane bugs from spreading.

2. Stage 8: implement SFU RTL for RCP/EXP2 with special-value tests and error
   sweeps against the golden model.

3. Stage 9: implement FP8 E4M3FN decode/pack and MMA.m16n16k16.e4m3.f32 with
   strict k=0..15 accumulation order and fragment-layout tests.

4. Stage 10: build real XDMA/Vitis platform integration:
   command queue, address-window table, capability/fault CSRs, HBM mappings, and
   staged build scripts.

5. Stage 11: add PyTorch scoreable P0/P1 operators backed by runtime launches,
   then expand toward ResNet-50 and LLM priority paths.

6. Stage 12: PPA and submission hardening:
   multi-CU scale, timing closure, SLR floorplanning, HBM bandwidth, power,
   stability, benchmark reports, and final bitstream/xclbin.

## Bottom Line

The current project has a credible and tested foundation through Stage 7.3, but
it is still below scoreable contest readiness. The next correctness blocker is
not performance; it is completing predicate/fault semantics, then implementing
hardware SFU/MMA and real XDMA-backed runtime integration.
