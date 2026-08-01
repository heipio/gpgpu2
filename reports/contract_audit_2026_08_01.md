# Contract Audit: 2026-08-01

**Sources:** `contest.md`, `aec_g_isa_v1.json`, the current RTL/software tree,
and the supplied U280 toolchain notes.

## Evidence That Passed

- Python golden/compiler/assembler/contract/differential tests pass.
- Remote Vivado 2023.1 XSim regression passes with SFU LUT files staged and
  fatal/error text treated as a failure: SoC lifecycle, multiwarp scheduler,
  scoreboard/barrier, MMA, SFU, FPU, and warp collective testbenches.
- Current RTL package source list is explicit; IP-XACT regenerates and the XRT
  host driver compiles in the supplied Vitis 2023.1/XRT 2022.1 environment.
- The SoC launch mask was corrected from eight active bits to all 32 logical
  warp bits. The issue stage retains four 8-lane physical beats.

## Contract-Critical Gaps

1. The current full Vitis link at the requested 180 MHz failed routed timing:
   `clk_out1_ulp_clk_wiz_0` WNS is `-0.784 ns`. There is no current valid
   xclbin, and the old xclbin must not be used as evidence for current RTL.
2. The launch CSR ABI provides only start PC/START. It does not convey grid,
   block, parameter, or per-warp work assignment. Starting all resident warps
   therefore duplicates a kernel's instruction stream. This does not satisfy
   the multi-warp/block completion requirement of contest section 5.2.
3. The RTL implements only one CU and a single in-order LSU request stream,
   despite exposing four HBM masters through an address router. It does not
   yet demonstrate concurrent independent HBM traffic or the required
   bandwidth measurements.
4. `.pmem` and `.smem` are encoded by the assembler but have no verified
   functional memory implementation; cache/scratchpad coherence and DMA
   visibility are likewise not demonstrated.
5. `runtime/aec_runtime.cpp` is a host-shadow implementation. It does not
   submit XDMA command packets, drive the real launch ABI, poll completion,
   recover a hung dynamic region, or report hardware counters.
6. The PyTorch layer blocks scoreable FP8 GEMM and only permits debug CPU
   fallback. ResNet-18, ResNet-50, and Transformer scheduling/accuracy runs
   are absent.
7. Randomized RTL-vs-golden coverage is incomplete for SFU/MMA/FP32 special
   values, full 32-lane SIMT programs, fault paths, and memory ordering.
8. IP-XACT intentionally leaves FREQ_HZ flexible for Vitis link configuration;
   this avoids a hard-coded 200/300 MHz contract but leaves nonfatal
   `IP_Flow 19-11770` and SystemVerilog-wrapper `IP_Flow 19-5654` notices.

## Submission Gate

The project is a verified RTL/software bring-up, not a contest-complete
submission. Closure requires a correct launch/work-dispatch ABI, real XDMA
runtime path, working multi-CU/memory system, scoreable model operators,
routed WNS >= 0, a newly generated xclbin, board correctness/stability/power
logs, and final workload accuracy/performance evidence.
