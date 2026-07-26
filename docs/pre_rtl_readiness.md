# Pre-RTL Readiness Checklist

This document freezes the Stage 1 and Stage 2 contracts before RTL begins.

## Go / No-Go Summary

GO for RTL bring-up of fetch/decode, GPR/predicate state, scalar LD/ST, SIMT PC/mask, and command queue skeleton. Do not begin FP8 MMA or model acceleration RTL until scalar trace diff and memory-window tests pass.

## Fixed Contracts

- AEC-G v1.0 uses fixed-width 128-bit instructions and headerless `.aecbin` files.
- `.aecbin` stores four little-endian 32-bit words per instruction: w0 is bits 31:0, w1 is bits 63:32, w2 is bits 95:64, and w3 is bits 127:96.
- Opcode bits are 127:112; pred/control bits are 111:96; dst bits are 95:80; src1 bits are 79:64; src2/imm32 bits are 63:32; src3/immext bits are 31:0.
- E4M3FN FP8 uses round-to-nearest-even/RNE, canonical NaN, full subnormal decode in golden model, and overflow saturation to signed max finite 448.
- Optional E5M2 is not enabled in baseline capability.
- Inactive lanes are write-masked and silent: no GPR, predicate, memory, counter, or exception update.
- REDUCE.ADD.f32 skips inactive lanes without injecting +0.0 and uses the balanced tree over ascending logical lane IDs.
- Cross-beat SHFL/REDUCE must see all 32 logical lanes when physical_simd_lanes < logical_warp_width.
- 64-bit `.b64` values use even register pairs `{Rk+1,Rk}`.
- MMA A/B fragments are even aligned; MMA C/D fragments are 8-register aligned.
- Base AEC-G has no single-instruction `.b128` load/store; compiler lowers b128 into legal b32/b64 LD/ST.
- Runtime device pointers are 64-bit. RTL sees 32-bit address registers through an address-window table. Silent 64-bit pointer truncation is forbidden.
- Unaligned unsupported access must raise MISALIGNED_ACCESS or be split with identical semantics.

## SIMT / Control

- BRX must execute both taken and fall-through paths under the correct masks.
- SSY/SYNC maintain a reconvergence stack and underflow/overflow must raise SIMT_STACK_FAULT.
- BAR.SYNC with expected_warps=0 synchronizes all currently non-halted warps in the CTA, requiring dynamic active-warp tracking.

## Runtime / Memory Ordering

- FENCE subop=0 is CTA scope; FENCE subop=1 is DEVICE scope.
- Runtime must insert soft or MMIO fence control around H2D, launch, synchronize, and D2H boundaries until the final RTL register map is implemented.
- Launch must publish parameter memory, address-window table, module pointer, grid/block dimensions, and dynamic shared memory before doorbell.
- D2H must not begin until device stores are visible and cache flush/invalidate policy has completed.

## SFU RTL Contract

- RCP.f32 max relative error <= 2^-10.
- EXP2.f32 max relative error <= 2^-9 in normal result range.
- SFU special-value mapping is architectural: RCP(+/-0)->+/-Inf, RCP(+/-Inf)->+/-0, EXP2 overflow->+Inf, EXP2 underflow->+0, NaN->canonical NaN.
- Use ready/valid arbitration and request tags carrying CU, warp, lane mask, destination register, and instruction identity.
- Prefer LUT/range-reduction/interpolation/refinement SFU architecture; avoid unbounded combinational math.

## U280 / Physical Planning

- Starter target: 2 CUs, then 4 CU reference scale.
- Physical SIMD lanes: 8, issue_beats_per_warp: 4.
- Start near 180 MHz; target 200 MHz after routing evidence.
- Review per-SLR utilization, cross-SLR pipeline stages, register slice placement, HBM port mapping, and top timing paths after every major RTL change.
- Use at least 4 independent HBM pseudo-channels initially; target 8-16 HBM ports.
- U280 platform name for final evidence: U280 Gen3x16 XDMA base_1.
- Keep `connectivity.cfg` explicit for HBM mappings once Vitis integration begins.
- Before real board mode, unset XCL_EMULATION_MODE and record xbutil evidence.

## PyTorch / Model Scoring Guardrails

- Fallback logging must include fallback true/false, reason, CPU time, input bytes, output bytes, call count, operator/model name, and scoreable-main-compute flag.
- Legal CPU layout transform, padding, tensor blocking, byte packing, pinned memory, and DMA descriptor generation are allowed before H2D.
- Scoreable model main compute must log fallback=false.
- LLM argmax must execute on device with smallest-token tie break.
- EOS padding: after EOS, fill remaining positions up to max_new_tokens=128 with eos_token_id.
- Latency mode uses queue_depth=1, concurrency=1, and dynamic batching disabled.
- Clear warm-up contamination, input-derived activations, output buffers, lookup/hash caches, and KV cache at request/shape/model/public-hidden boundaries.

## Current Test Gates

- tests/test_sim.py
- tests/test_compiler.py
- tests/test_sim_ctrl.py
- tests/test_differential.py

All pass locally and on remote CentOS 7.9 / Python 3.6 as of 2026-07-26.

## RTL Entry Order

1. Define RTL instruction decoder from `aec_g_isa_v1.json` bit fields.
2. Add trace output matching simulator fields: pc, active_mask, predicate writes, GPR writes, memory writes, faults.
3. Implement NOP/MOV/IADD/LD/ST/HALT first.
4. Run vector-add differential trace against `tests/test_differential.py` generated machine code.
5. Add BRX/SSY/SYNC and run SIMT stack tests.
6. Add FENCE/BAR.SYNC soft semantics and fault plumbing before SFU/MMA.
7. Add REDUCE and SHFL cross-beat tests before trusting physical_simd_lanes < 32.
8. Add SFU, then FP8 conversion, then MMA strict k=0..15.

## Known Not-Blocking For RTL Start

- No bitstream/xclbin yet.
- No timing/util/power reports yet.
- No one-click final build flow yet.
- Runtime is host-shadow and not XDMA-backed yet.
- PyTorch FP8 GEMM scoreable path is intentionally blocked until a real AEC kernel exists.
- Open bonus manifest is intentionally deferred until baseline correctness and model gates pass.

## Audit-Compatible Future-Stage TODO Terms

These are explicitly tracked as future-stage requirements, not claimed as complete before RTL:

- 64-bit pointer truncation guard: runtime must reject every pointer/window argument that cannot be represented safely in the 32-bit AEC address window.
- DDR4 capacity tier: DDR4 is reserved for cold weights, datasets, overflow, and staging while hot activations/KV/tensor tiles default to HBM.
- fallback I/O bytes: PyTorch fallback logs must include input bytes and output bytes for every operator.
- on-device LLM argmax: LLM decode argmax must run on FPGA/device, with smallest-token tie break.
- warm-up contamination: clear input-derived state after warm-up and before measured public/hidden phases.
- state reset: runtime/PyTorch must expose request, shape, model, and phase boundary reset hooks.
- legal CPU layout transform: CPU may do layout transform, padding, tensor blocking, byte packing, pinned-memory setup, and DMA descriptor generation before H2D only.
- WNS/timing evidence: final reports must include timing summaries and WNS for every scoring clock.
- zero timing violations: submitted routed implementation must have WNS >= 0 and no timing violations.
- energy efficiency: collect board power and endpoint images/J or tokens/J during formal windows.
- thermal/power reset: thermal reset, power-limit reset, watchdog reset, or instability during long run is a failure to record and fix.
- anti-hardcode unknown kernel: compiler/runtime/RTL must not dispatch by kernel name, model name, shape, hash, `.aecbin` fingerprint, layer name, or hidden-output lookup.
- open bonus manifest: deferred until baseline correctness and model accuracy gates pass.
- open bonus baseline prerequisite: no bonus work before baseline 25-point correctness, FP8/SFU, runtime legality, and ResNet/LLM gates pass.
- one-click or staged build script: final submission needs Make/CMake/bash staged reproduction flow.
- U280 platform name: U280 Gen3x16 XDMA base_1.
- explicit HBM port mapping: `connectivity.cfg` must map AXI/kernel ports to explicit HBM pseudo-channels.
- local/official tool mismatch: local notes mention Vitis/Vivado 2023.1, but final evidence must prove Vivado/Vitis 2022.2 compatibility.
- LLM 18-point priority: optimize LLM only after legality/correctness gates pass, with prefill/decode/E2E metrics.
- ResNet-50 12-point priority: prioritize ResNet-50 throughput after baseline op correctness and accuracy gates pass.

## Exact Audit Needles

- truncate: never truncate 64-bit runtime pointers into 32-bit AEC address registers; use address-window metadata and reject unsafe mappings.
- input/output bytes: fallback audit records must contain input/output bytes, fallback flag, reason, CPU time, call count, operator, and model.
- argmax on device: LLM next-token argmax on device is mandatory for scoreable decode.
- Warm-up: Warm-up inputs must not contaminate measured public/hidden phases; clear state after Warm-up.
- state-reset: runtime and PyTorch must expose state-reset hooks at request, shape, model, and phase boundaries.
- layout transformation: legal CPU layout transformation is allowed before H2D only when it does not compute model math.
- hardcoded: hardcoded output, kernel-name dispatch, shape fingerprinting, model fingerprinting, and `.aecbin` hash shortcuts are forbidden.
- open_bonus_manifest: defer open_bonus_manifest until baseline correctness gates pass.
- build scripts: use staged build scripts for compiler/runtime tests now and final RTL/bitstream reproduction later.
- xilinx_u280_gen3x16_xdma_1_202211_1: final platform target.
- HBM[: explicit HBM[0], HBM[1], HBM[2], ... mappings must appear in connectivity.cfg when Vitis integration begins.
- version mismatch: local Vitis/Vivado 2023.1 versus official 2022.2 is a version mismatch risk to document.
- 18 points: LLM is 18 points and should be prioritized after correctness gates pass.
- 12 points: ResNet-50 is 12 points and should be prioritized after baseline op correctness.
