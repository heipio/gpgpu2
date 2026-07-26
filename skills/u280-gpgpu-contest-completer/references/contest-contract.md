# Contest Contract

This reference distills the U280-GPGPU contest statement into implementation constraints. Use it as an operating checklist; the official `contest.md` remains authoritative when available.

## Goal

Build a programmable GPGPU prototype on one Alveo U280 FPGA card, covering:

```text
PyTorch model/op
  -> graph/op backend and runtime
  -> PTX restricted subset / AEC assembly / AEC machine code
  -> compiler, scheduling, kernel launch
  -> XDMA driver and host runtime
  -> U280 GPGPU RTL
  -> HBM2 / DDR4
```

The contest rewards software/hardware co-design under fixed interfaces, not a clone of a commercial GPU.

## Fixed Interfaces

### AEC-G ISA

- AEC-G v1.0 is the only scoreable hardware program interface.
- RTL must execute the official AEC-G instruction semantics.
- Internal microcode, arrays, and private control signals are allowed.
- Do not alter AEC instruction encodings, ABI, `.aecbin` layout, register meanings, predicates, active masks, MMA fragments, address spaces, exceptions, or observable behavior.
- Optional features must be declared by capability and cannot be required for baseline correctness.
- Base AEC-G v1.0 uses 128-bit fixed-width instructions and does not include `.b128` single-instruction load/store. Use multiple 32/64-bit operations unless a vector-memory extension is declared.
- 64-bit values use even-aligned register pairs `{Rk+1, Rk}`. MMA A/B fragment starts must be even-aligned and C/D fragment starts must be 8-register aligned.
- FP32 operation order is visible for tests. MMA accumulates in strict `k=0..15` order, and `REDUCE.ADD.f32` follows the golden balanced binary tree over ascending logical lanes.
- `MAD.f32` and `FMA.f32` are numerically different: `MAD.f32` rounds the multiply and then rounds the add, while `FMA.f32` performs one fused final rounding. Do not collapse MAD into FMA in RTL or the simulator.
- NaN and subnormal behavior is part of the ABI contract. Canonicalize NaN unless payload preservation is explicitly specified, and declare flush-to-zero versus full subnormal behavior in the manifest/capability so RTL, simulator, and tests match.
- Inactive lanes masked by active mask or predicate must not update registers, predicates, memory, counters, or exception state.
- Runtime device pointers are 64-bit, while base `LD/ST` address registers are 32-bit. Hardware and runtime must provide an address-window, buffer-table, or base-register translation mechanism for HBM/DDR addresses; truncating 64-bit pointers is invalid.
- `FENCE` must support `subop=0` for CTA scope and `subop=1` for DEVICE scope. Runtime cache flush/invalidate is required at launch/copy/sync boundaries if DMA and device caches are not coherent.

### AEC Runtime

- The fixed CUDA-like runtime API is the only scoreable application/device interface.
- PyTorch package, op library, model scheduling, autotuning, and benchmark scripts must use runtime memory management, H2D/D2H, module load, kernel launch, sync, error, and counter APIs.
- Runtime must read hardware capability registers and compare them with the `.aecbin` manifest before module load or launch. Unsupported warp width, numeric mode, shared memory size, vector memory, or extension requirements must return `AEC_ERROR_UNSUPPORTED_FEATURE`.
- Private model-specific APIs, direct scoring-script MMIO, private ioctl entry points, and hardwired model triggers are disallowed.

## Mandatory Capabilities

- Place all scoreable hardware logic in the specified U280 XDMA dynamic region.
- Implement core processor logic in RTL or auditable RTL generation.
- Implement AEC-G v1.0 fixed ISA/ABI.
- Trigger model computation through AEC instruction streams: memory access, SIMT scalar instructions, MMA, SFU, reduction, and synchronization.
- Implement the fixed CUDA-like runtime API.
- Implement PTX-to-AEC mapping, assembly/loading, and compile reports. `nvcc` may be used only for CUDA `.cu` to PTX.
- Implement XDMA-based driver/control path for command submission, DMA, sync, error recovery, and counters.
- Pass public, randomized, hidden, and post-contest unknown-kernel tests.
- Submit reproducible RTL, project files, bitstream/xclbin, software source, reports, logs, and design documentation.

## Prohibited Shortcuts

- No precomputed outputs based on test names, model names, shapes, kernel names, `.aecbin` fingerprints, hashes, sample IDs, offsets, or hidden input statistics.
- No hardwired ResNet/Transformer/fixed-shape state machines that bypass AEC instruction semantics.
- No input/weight/activation/KV-cache-dependent CPU numerical compute inside scoring windows.
- No CPU-side LLM decode argmax. The FPGA must choose the next token, and ties choose the smallest token ID.
- No cross-request, cross-shape, cross-model, or cross-phase reuse of input-derived activations, outputs, lookup/hash caches, random-test intermediates, or LLM KV cache.
- No latency-mode dynamic batching, queue accumulation, future-request waiting, EOS-denominator manipulation, early-stop denominator reduction, or selective reporting of successful rounds.
- No silent data corruption for unsupported memory behavior. Unaligned accesses must be split correctly or fault; DMA/cache visibility must be defined and enforced.
- No silent 64-bit-to-32-bit device pointer truncation. Any address that cannot be represented through the runtime/hardware address-window contract must be rejected before launch.
- No complete closed-source DPU/GPU/NPU core substitution.
- No modifications to card electrical parameters, thermal protection, platform static region, timing tools, drivers, or scoring scripts.
- No network access, hidden reference output reads, cross-round hidden-input cache reuse, or selective success reporting.

## Allowed Building Blocks

- AMD/Xilinx storage, PCIe/XDMA, clock, FIFO, floating-point, AXI, HBM, and DDR controller IP.
- HLS for non-core auxiliary modules.
- Dedicated MMA, SFU, reduction, copy, prefetch, and DMA engines when driven by AEC programs or ABI descriptors.
- DDR4 for large weights, datasets, or overflow data, with HBM/DDR traffic reported.
- Incomplete CUDA/PTX/IEEE-754 coverage, provided the required subset and official models work.
- E5M2 FP8 is optional. If implemented, declare it in capability and follow IEEE-like zero/subnormal/normal/Inf/NaN behavior.
- CPU-side layout transformation, byte packing, padding, tensor blocking, shape/stride metadata handling, pinned-memory setup, and DMA descriptor generation are allowed before H2D transfer when they do not compute input/weight-dependent numerical results.
- Bitstream, weights, compiled AEC kernels, and input-independent autotune results may remain resident across formal runs when logged. Input-related buffers, intermediate results, output caches, lookup/hash caches, and KV cache must be cleared at required phase boundaries.
- Legal CPU whitelist work still needs audit logging per operator: `fallback=false/true`, reason, CPU time, input bytes, output bytes, call count, and operator/model name.

## Platform

Formal reports and scoreable runs use:

- Server: NF5468M5, 64 CPU cores, 768G memory.
- OS: CentOS Linux 7.9, kernel `3.10.0-1160.108.1.el7.x86_64`, GLIBC `2.17`.
- Vivado/Vitis: `2022.2`.
- XRT: `2.13.479`, branch `2022.1`, hash `5e92a513c6950e79638b1a879ddb882da34fc683`.
- Shell: `U280 Gen3x16 XDMA base_1`.

Record `xbutil examine`, shell/platform, shell UUID, BDF, XRT, XOCL/XCLMGMT, Vivado/Vitis, and Linux kernel in scoring logs.

### Strict Environment Lock

Generated code, scripts, RTL, containers, and documentation must be compatible with the official environment. A clean design that silently requires a newer GLIBC, newer XRT, newer Vivado Tcl command, newer IP catalog, or unconfirmed compiler toolchain can fail before scoring starts.

Use these rules by default:

- Target CentOS 7.9 and GLIBC 2.17 for host binaries.
- Target Vivado/Vitis 2022.2 and XRT 2.13.479 APIs.
- Target the U280 Gen3x16 XDMA base_1 shell and its dynamic-region constraints.
- Avoid C++17/C++20-only features, modern libstdc++ ABI assumptions, and newer CMake defaults unless the official image confirms a matching devtoolset.
- Pin Python packages, compiler flags, linker flags, Tcl scripts, IP versions, and container base images in reproducibility docs.
- Treat version mismatch as a submission risk, not a local convenience issue.

When in doubt, generate conservative C/C++, plain Make/CMake, and Vivado 2022.2-compatible Tcl, then document any confirmed newer toolchain layer explicitly.

## U280 Resources

Public card resources: 1,304K LUT, 2,607K registers, 9,024 DSP, 2,016 BRAM, 960 URAM, 8 GB HBM2, 32 GB DDR4.

Approximate XDMA dynamic-region resources:

| Resource | SLR0 | SLR1 | SLR2 | Total |
|---|---:|---:|---:|---:|
| CLB LUT | 386K | 364K | 381K | 1,131K |
| CLB Register | 773K | 729K | 763K | 2,265K |
| BRAM36 | 600 | 576 | 600 | 1,776 |
| URAM | 320 | 320 | 320 | 960 |
| DSP48E2 | 2,664 | 2,784 | 2,856 | 8,304 |

Conservative starter envelope:

| Item | Reference Envelope |
|---|---:|
| LUT | <= 565K |
| Register | <= 1,133K |
| BRAM36 | <= 888 |
| URAM | <= 480 |
| DSP48E2 | <= 4,152 |
| User clock | baseline 180 MHz, target 200-225 MHz, advanced 250 MHz |

Per-SLR review matters because U280 routing failures often appear before full-card resources are exhausted. Treat these as review targets for a starter design:

- Keep LUT/register/BRAM/URAM near or below about 50% of the dynamic-region envelope until the board path is stable.
- Keep DSP use near or below about 55% of each SLR dynamic-region DSP budget for starter RTL.
- After every major RTL change, review utilization by SLR, HBM/AXI placement, clock-region pressure, and top timing paths.
- Add register slices or pipeline stages on cross-SLR AXI, HBM, command, reduction, broadcast, scoreboard, and wide GEMM/control paths before chasing higher frequency.
- Do not judge feasibility from aggregate full-card utilization alone.

## Logical Warp Rules

- `logical_warp_width`: architecture-visible threads per warp; official AEC-G v1.0 score config is 32.
- `physical_simd_lanes`: actual hardware SIMD lanes per cycle; a microarchitecture parameter.
- `issue_beats_per_warp = logical_warp_width / physical_simd_lanes`; division must be exact.
- Lane IDs, predicates, active masks, shuffles, reductions, and MMA fragments are logical-warp concepts.
- Physical lanes may be reused across issue beats but must not change observable logical semantics.
- When `physical_simd_lanes` is less than 32, `SHFL` and `REDUCE` must operate across all logical lanes, not only the current issue beat. RTL needs a warp buffer, bypass network, or equivalent replay path for cross-beat operands.
- Divergent `BRX` must execute both taken and fall-through paths under the correct masks. `SSY`/`SYNC` maintain a reconvergence stack; overflow or underflow raises `SIMT_STACK_FAULT`.
- `BAR.SYNC expected_warps=0` synchronizes all currently non-halted warps in the block, so hardware needs a dynamic active-warp count per block.

## Reference Baseline

Reference starter scale:

- 4 CUs, SLR distribution 1/2/1 or separated control/HBM-heavy logic.
- `logical_warp_width=32`; reference `physical_simd_lanes=8`; 4 issue beats per warp.
- 4 resident warps per CU, later 8 after validation.
- Per-CU 8 INT32 lanes; FP32 add/mul can be shared or time-multiplexed.
- Per-CU 64 KiB register file, 32-bit word, banked.
- At least 8 predicate bits per logical thread and one 32-bit active mask per logical warp.
- 2-4 full-card logical FP8 16x16 tiles.
- Per-CU 16 KiB shared plus 8-16 KiB L1D, or unified 24-32 KiB.
- Full-card 1-2 MiB L2 or explicit scratchpad.
- At least RCP and EXP2 SFU path.
- Start with 4-8 HBM AXI master ports; expand after verification.
- Use HBM2 for high-bandwidth hot data: activations, KV cache, frequently accessed weights, tensor tiles, command queues, and scratch buffers.
- Use DDR4 as a lower-bandwidth capacity tier for cold weights, large datasets, overflow, or staging when a model exceeds the comfortable HBM working set.
- Runtime, PyTorch, reports, and `design.json` should make HBM/DDR placement explicit rather than hiding all `.gmem` behind one opaque allocator.

Starter resource target: roughly 350K-450K LUT, 350-550 BRAM36, 120-200 URAM, 800-1,200 DSP, 180-200 MHz.

SFU starter architecture:

- Prefer BRAM/URAM/distributed-ROM lookup tables with range reduction and reconstruction.
- Use linear interpolation, segmented low-order polynomial correction, or one Newton-Raphson refinement when needed.
- Pipeline lookup, interpolation, refinement, and writeback; carry warp/lane tags through the pipeline.
- Share one SFU across 2-4 CUs at first if resources or routing are tight.
- When sharing an SFU across CUs or warps, use ready/valid arbitration and carry CU/warp/lane/destination tags so out-of-order completions cannot write back into the wrong request.
- Avoid a large fully combinational SFU and avoid DSP-heavy Taylor-series designs unless utilization, timing, and error reports justify them.
- Hard-code special-value behavior before approximation: RCP maps `+/-0` to `+/-Inf` and `+/-Inf` to `+/-0`; EXP2 overflow maps to `+Inf` and underflow to `+0`; optional RSQRT maps `+0` to `+Inf` and negative inputs to canonical NaN.

## LLM Decode Rules

- Greedy argmax for next-token selection runs on the FPGA. Returning full logits to CPU for argmax is banned in scoreable decode.
- Tie-breaking selects the smallest token ID.
- Generate exactly 128 positions per sequence for formal throughput accounting.
- In batched decode, once a sequence emits `eos_token_id`, all later positions for that sequence are filled with `eos_token_id` while other sequences continue normally.
- Hidden prompts may be arranged to expose stale KV cache, wrong EOS masking, CPU argmax, or early-stop denominator manipulation.

## Required Submission Tree

```text
rtl/
constraints/
platform/
driver/
runtime/
compiler/
pytorch/
tests/
bitstream/
reports/
docs/
design.json
```

`design.json` should record CU count, `logical_warp_width`, `physical_simd_lanes`, `issue_beats_per_warp`, cache sizes/design, GEMM tile count and shape, frequency, numeric modes, runtime capability, HBM/DDR placement policy, and driver version. Keep key names stable and machine-readable so official or local scripts do not have to infer them from prose.
