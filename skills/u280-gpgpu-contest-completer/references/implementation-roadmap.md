# Implementation Roadmap

Use this roadmap to turn the contest contract into an executable project.

## Phase 0: Repository and Contract Audit

Deliver:

- Gap report against the required tree.
- Current architecture summary.
- Risk list: ISA divergence, runtime API mismatch, CPU fallback, missing compiler, missing board evidence, timing risk.
- Environment compatibility report: CentOS 7.9, GLIBC 2.17, Vivado/Vitis 2022.2, XRT 2.13.479, shell/platform, compiler standard, and container base image.
- Initial `design.json`.

Recommended command:

```bash
python skills/u280-gpgpu-contest-completer/scripts/audit_submission.py <repo-root>
```

## Phase 1: AEC-G Golden Infrastructure

Build the shared truth before optimizing hardware:

- `aec_g_isa_v1.json`: opcode, type, space, predicate, special registers, MMA layout, SFU functions, error codes, feature bits.
- Assembler and disassembler for 128-bit fixed-width instructions.
- Golden instruction simulator for scalar ISA, SIMT control, memory, FP8 conversions, MMA, SFU, shuffle, reduction, atomics, fences, barriers, and faults.
- Manifest validator for `.aecbin` and runtime launch metadata.
- Numeric conformance assertions that are shared by software tests and RTL testbenches.

Key ISA facts:

- Instruction width: 128 bit.
- Fields: opcode `[127:112]`, pred_ctrl `[111:96]`, dst `[95:80]`, src1 `[79:64]`, src2/imm32 `[63:32]`, src3/immext `[31:0]`.
- `.aecbin` has no header; each instruction is four little-endian 32-bit words: `w0=bits[31:0]`, `w1=bits[63:32]`, `w2=bits[95:64]`, `w3=bits[127:96]`.
- PC is instruction-indexed, not byte-indexed.
- Reserved opcode/type/space must raise `ILLEGAL_INSTRUCTION`, not behave as NOP.
- Predicate or active-mask disabled lanes are silent: no GPR, predicate, memory, counter, or exception update.
- Base AEC-G v1.0 has no `.b128` load/store. Lower vector memory into 32/64-bit `LD/ST` unless a compatible vector-memory capability is declared.
- 64-bit scalars and `.b64` memory use even-aligned register pairs `{Rk+1, Rk}`.
- Runtime/API device addresses are 64-bit, but base AEC-G `LD/ST` address registers are 32-bit. Define a buffer table, base-register table, or address-window ABI before writing kernels; never let compiler/runtime truncate device pointers.
- `FENCE` baseline subops are required: `subop=0` CTA and `subop=1` DEVICE.
- MMA fragment alignment: A/B start registers are even-aligned; C/D start registers are 8-register aligned.
- Floating-point order is fixed for reproducibility: MMA accumulates in strict `k=0..15` order using FP32 FMA; `REDUCE.ADD.f32` uses the balanced binary tree over ascending logical lanes with steps 1, 2, 4, and so on.
- `MAD.f32` performs multiply rounding followed by add rounding; `FMA.f32` performs one fused final rounding.
- NaN canonicalization and subnormal handling must be declared in the manifest/capability and implemented identically in simulator and RTL.

Mandatory opcode groups:

- Arithmetic: `ADD/SUB/MUL/MAD/FMA`.
- Logic: `AND/OR/XOR/NOT/SHL/SHR/SAR`.
- Predicate/select: `SETP/CMPP/SEL`.
- Memory: `LD/ST/ATOM/FENCE`, optional `PREFETCH`.
- Control: `BR/BRX/SSY/SYNC/BAR/HALT`.
- Move/convert: `CPY/LOADI/LOADI64/CVT/PACK/UNPACK`.
- Warp: `SHFL/REDUCE`.
- Matrix: `MMA`.
- SFU: `SFU`.
- `NOP`.

## Phase 2: Compiler Toolchain

Minimum scoreable path:

```bash
nvcc -ptx kernel.cu -o kernel.ptx
compiler/aec-cc kernel.ptx -O2 -o kernel.aecbin --report compile_report.json
```

Implement:

- PTX 9.3 restricted-subset parser.
- Type checker, CFG, basic blocks.
- Lowering to AEC-G v1.0.
- Register and predicate allocation.
- Branch target fixups.
- Parameter ABI and 64-bit pointer pair handling.
- Address-window lowering for 64-bit runtime pointers into 32-bit ISA-visible addresses, with diagnostics when a buffer cannot be represented safely.
- Dynamic shared-memory ABI: consume manifest `dynamic_smem_bytes`, compute static/dynamic `.smem` layout, emit launch metadata, and diagnose layouts exceeding per-CU shared-memory capacity.
- Instruction selection.
- `.b128` and vector memory lowering into legal 32/64-bit AEC `LD/ST`, or capability-gated vector-memory emission.
- Register-alignment diagnostics for 64-bit pairs and MMA fragments.
- Rejection of illegal base ISA encodings before `.aecbin` emission.
- `.aecbin` emission.
- JSON compile report: instruction count, registers, predicates, spill, shared memory, estimated occupancy, used extensions, diagnostics.
- Disassembler for evidence and debugging.

Baseline optimizations:

- Constant folding.
- Dead-code elimination.
- Simple common subexpression elimination.
- Address calculation simplification.
- Simple instruction scheduling or explicit scoreboard-safe stalls.

Performance optimizations:

- Tiling, vectorization lowering, double buffering, software pipeline.
- GEMM intrinsic selection.
- Layout transforms.
- Operator fusion.
- Shape specialization only through manifest/capability, not through hidden-test fingerprints.
- No kernel-name, shape-hash, layer-name, or model-fingerprint replacement with hardcoded AEC binaries. Pattern recognition is allowed only as general compiler optimization that preserves unknown-kernel semantics.
- Autotuning with logged, reusable, input-independent choices.

## Phase 3: RTL Core

Bring up incrementally:

1. Command queue, doorbell, completion queue, status and counters.
2. Fetch/decode of 128-bit instructions.
3. Per-warp PC, active mask, predicate state.
4. GPR file, register pairs, bank conflict stalling.
5. Scoreboard or static scheduling contract.
6. Scalar VALU.
7. Load/store to `.pmem`, `.smem`, `.gmem`.
8. Branch divergence and reconvergence.
9. Barrier and block/kernel completion.
10. Fault capture and watchdog.
11. Shuffle/reduction across full logical warp, including cross-issue-beat behavior.
12. FP8 conversion and PACK/UNPACK.
13. MMA.
14. SFU.
15. Atomics and fences.

Required hardware commands:

- Buffer allocation/registration.
- H2D, D2H, optional D2D.
- `.aecbin` load.
- Parameter-region write.
- `gridDim`, `blockDim`, dynamic shared memory configuration.
- Launch, wait, timeout, abort/reset.
- Status/error/counter reads.

SIMT control details:

- For divergent `BRX`, execute both taken and fall-through paths under their active masks; do not drop either side for convenience.
- `SSY`/`SYNC` push and pop reconvergence PC/mask entries. Stack overflow or underflow must produce `SIMT_STACK_FAULT` with fault PC and CU/warp/block metadata.
- `BAR.SYNC expected_warps=0` means all currently non-halted warps in the block, not all statically possible warps. Track active warp count dynamically as lanes/warps halt.
- Cross-beat `SHFL` and `REDUCE` must see all 32 logical lanes even when only 4/8/16 physical lanes issue per beat. Add a warp-level value buffer, scoreboarded bypass, or replay sequence so source lanes from earlier/later beats are available.
- Every writeback path must include active-mask and predicate write-enable gating, including `SETP/CMPP`, memory faults, SFU, MMA, and reductions.

## Phase 4: Memory System

Address spaces:

| Space | Purpose | Minimum |
|---|---|---|
| `.gmem` | HBM/DDR global memory | byte address, at least 32-bit visible address; runtime API uses 64-bit device address |
| `.pmem` | kernel parameters | read-only or written before launch |
| `.smem` | block shared memory | visible within block, barrier communication |
| `.lmem` | private spill/local | optional |
| `.cmem` | constants | optional |

Rules:

- Define unaligned access, out-of-bounds access, cache coherence, and DMA synchronization.
- Implement the 64-bit-to-32-bit address-window contract for `.gmem`: map runtime device pointers to window/base metadata and check that every kernel argument uses the intended HBM/DDR physical range.
- If only naturally aligned access is supported, reject or fault unsupported cases.
- Flush/invalidate at launch boundaries if DMA and device caches are not coherent.
- Treat unsupported unaligned access as a correctness event: either split it with identical architectural semantics or raise `MISALIGNED_ACCESS` with fault PC/CU/warp/block information.
- Test H2D -> device load, device store -> D2H, DMA while cache contains stale lines, `FENCE.CTA`, `FENCE.DEVICE`, and runtime flush/invalidate transitions.
- Use at least 4 independent HBM pseudo-channels; report bank mapping and conflict behavior.
- Avoid serializing all CUs through one AXI master.
- Dynamic shared memory is a launch-time allocation. Check `dynamic_smem_bytes` plus static `.smem` against the physical per-CU BRAM/URAM budget and expose errors before the kernel overwrites another block.

HBM2 + DDR4 placement strategy:

- Treat HBM2 as the default high-bandwidth working memory for hot activations, KV cache, frequently reused weights, tensor tiles, scratch buffers, command queues, and performance-critical `.gmem` windows.
- Treat DDR4 as a second-level capacity pool for cold weights, large datasets, overflow buffers, checkpoint staging, or model variants that do not fit comfortably in the 8 GB HBM working set.
- Add runtime placement flags or policies so `aecMalloc`/module load can choose HBM, DDR, or explicit bank groups when the manifest requests it.
- Log HBM bytes, DDR bytes, bank conflicts, placement decisions, and any migration/copy cost.
- Keep the golden model and PyTorch wrapper aware of placement metadata without changing AEC-G observable memory semantics.

SLR and timing strategy:

- For starter RTL, review full-card and per-SLR utilization against the conservative envelope: around 350K-450K LUT, 350-550 BRAM36, 120-200 URAM, 800-1,200 DSP, and 180-200 MHz.
- Keep per-SLR DSP pressure near or below about 55% and keep LUT/register/BRAM/URAM close to the 50% reference envelope until routed timing and board stability are proven.
- Insert register slices or pipeline stages on cross-SLR AXI, HBM, command, scoreboard, broadcast, reduction, and wide GEMM/control paths.
- Keep CUs, local register files, shared memory, and local L1 paths physically close when possible; avoid one central always-on cross-SLR control bottleneck.
- Store utilization, timing path, SLR crossing, and pblock reports in `reports/`.

## Phase 5: FP8, MMA, and SFU

FP8:

- Required input format: E4M3FN.
- Optional: E5M2 with capability bit and IEEE-like zero/subnormal/normal/Inf/NaN behavior.
- Conversions use round-to-nearest-even unless integer conversion explicitly uses round-toward-zero.
- E4M3FN has no Inf, finite max abs 448, NaN maps to canonical NaN, overflow saturates to max finite.
- Scale must be explicit in ABI and reproducible in the golden model.
- Testbench assertions must cover signed zero, subnormal rounding, normal rounding ties, max finite saturation at 448, canonical NaN, optional E5M2 feature rejection/acceptance, and identical public/hidden rounding behavior.
- The manifest must state subnormal behavior. If hardware uses flush-to-zero for a type or path, the simulator and capability must say so; hidden tests should never discover an undocumented mismatch.

FP32 arithmetic:

- `MAD.f32` and `FMA.f32` require separate golden cases around cancellation, overflow boundary, and rounding ties.
- Do not implement `MAD.f32` by directly reusing a fused FMA datapath unless the datapath explicitly inserts the mandated intermediate rounding.

MMA:

- Required instruction: `MMA.m16n16k16.e4m3.f32 D, A, B, C`.
- Semantics: `D = A * B + C`.
- A/B are E4M3FN, C/D are FP32.
- Accumulate in strict `k=0..15` order using FP32 FMA.
- Do not reassociate, tree-reduce, fuse across `k`, or reorder the accumulation unless the official golden model changes.
- Must be executed by a full 32-thread logical warp. Partial active mask or predicate execution is illegal or must be rejected by compiler.
- Fragment layout must match the official logical-lane mapping and be represented in machine-readable ISA JSON.
- A/B fragment start registers must be even-aligned; C/D fragment start registers must be 8-register aligned.

Reduction:

- `REDUCE.ADD.f32` must use the official balanced binary tree over ascending logical lane IDs.
- The tree step sequence is `1, 2, 4, ...`; inactive logical lanes are skipped as specified by the golden model.
- Do not replace FP32 reduction with arbitrary serial order or implementation-dependent physical-lane grouping.

SFU:

- Required: `RCP.f32` and `EXP2.f32`.
- Optional: `RSQRT`, `LOG2`, `TANH`, `SIGMOID`, `SQRT`, `SIN/COS`.
- Must honor active mask and predicate.
- Must handle arbitration, back-pressure, tags, warp switching, and variable latency.
- Scoreboard/ready-valid must prevent early reads.
- Document special values, subnormal/flush behavior, approximation method, latency, initiation interval, resource use, and error.
- Prefer an FPGA-friendly implementation: range reduction, BRAM/URAM/distributed-ROM lookup tables, linear interpolation, segmented low-order polynomial correction, or one Newton-Raphson refinement.
- Pipeline every SFU stage and carry CU/warp/lane destination tags through the pipeline to avoid wrong-lane writeback under back-pressure.
- If one SFU services multiple CUs or warps, arbitrate requests with ready/valid, preserve request ordering where promised, and allow out-of-order completion only when tags make writeback unambiguous.
- Start with one shared SFU per 2-4 CUs when area is tight; replicate only if traces show SFU throughput is a model bottleneck.
- Avoid unbounded combinational math, unsynthesizable real-number code, and DSP-heavy Taylor expansions unless resource/timing/error evidence supports them.
- Special values are exact architectural cases, not approximation cases: `RCP(+/-0) -> +/-Inf`, `RCP(+/-Inf) -> +/-0`, `EXP2` overflow -> `+Inf`, `EXP2` underflow -> `+0`, optional `RSQRT(+0) -> +Inf`, and optional `RSQRT(negative) -> canonical NaN`.

Reference precision gates:

| Function | Minimum Accuracy |
|---|---:|
| RCP.f32 | max relative error <= 2^-10 |
| EXP2.f32 | max relative error <= 2^-9 in normal range |
| RSQRT.f32 if implemented | max relative error <= 2^-9 |

Model numeric gates:

| Task | Gate |
|---|---:|
| ResNet hidden Top-1 | drop <= 1.5 percentage points vs FP32 reference |
| ResNet hidden Top-5 | drop <= 1.0 percentage point vs FP32 reference |
| LLM perplexity | degradation <= 5% vs FP16 reference |
| LLM greedy token match | >= 95% |
| Public layer numeric tests | NRMSE <= 3% |

## Phase 6: Runtime and XDMA

Fixed API names:

```c
aecContextCreate(...);
aecMalloc(...);
aecFree(...);
aecMemcpyH2D(...);
aecMemcpyD2H(...);
aecModuleLoad(...);
aecKernelLaunch(...);
aecSynchronize(...);
aecGetLastError(...);
aecReadCounters(...);
```

Implement:

- Device open/init/capability read/error-state clear.
- Read-only capability registers for warp width, physical lanes, numeric modes, memory features, optional extensions, shared-memory limits, and resource limits.
- 64-bit device address allocation and HBM/DDR placement.
- H2D/D2H byte transfer with alignment, chunking, pinned memory, IOMMU handling, timeout handling.
- Module load: `.aecbin` plus manifest validation.
- Module load/launch capability check returning `AEC_ERROR_UNSUPPORTED_FEATURE` on unsupported manifest requirements.
- Launch: grid/block dimensions, parameters, dynamic shared memory, resources.
- Synchronization and error propagation.
- Counter read: cycles, memory bytes, cache misses, DMA time, kernel time, fault info.
- Hang recovery and dynamic-region reset.
- Logging of H2D/kernel/D2H time and CPU fallback status.
- Fallback log fields: `fallback=false/true`, reason, CPU time, input bytes, output bytes, call count, operator/model name, and whether the op is scoreable main compute.
- State reset APIs or internal hooks for phase/request/model/shape boundaries.
- KV-cache clearing for every LLM request unless the manifest explicitly describes a legal continuation within the same request.
- Input-derived activation/intermediate/output/lookup/hash-cache clearing after warm-up, between public/hidden phases, and between shape/model switches. Warm-up inputs must be separate from scoring inputs; clear state after warm-up before timed measurement.
- Explicit cache-coherence policy: `FENCE`, runtime flush/invalidate, uncached DMA window, or documented no-cache path.

CPU whitelist:

- Scheduling, shape/stride metadata, buffer management, DMA descriptors, module load, capability checks, launch/sync/error recovery, byte packing/copy, layout transformation, tensor blocking, padding, pinned-memory setup, IOMMU mapping, reading outputs for official scoring.

CPU banned during scoring:

- Convolution, GEMM/linear, attention, MLP, normalization, pooling, softmax, activation, reduction, argmax/sampling, dynamic quant/dequant/scale estimation, KV update, logits computation, hidden-output lookup.

## Phase 7: PyTorch Package

Minimum:

- Explicit PyTorch Tensor/device buffer conversion.
- Calls through fixed runtime API.
- Op-level correctness and error handling.
- Fallback logging with `fallback=false/true`, reason, CPU time, input/output bytes, and call count.
- Warm-up controls and timing statistics.
- E2E scripts for public models, ResNet-18, ResNet-50, and approximately 1B decoder-only Transformer.
- Legal CPU preprocessing path for layout transform, packing, padding, tensor blocking, and DMA descriptor preparation before H2D.
- Per-request reset path that clears output buffers, activation scratch, input-derived caches, and KV cache at scorer-defined boundaries.
- Separate latency and throughput scheduler configuration.

Op priorities:

| Level | Ops |
|---|---|
| P0 | copy, elementwise add/mul, ReLU, FP8 GEMM/linear |
| P1 | Conv2d lowering, bias, pooling, residual add |
| P2 | LayerNorm/RMSNorm, Softmax, GELU/SiLU, transpose/reshape |
| P3 | batched GEMM, QKV projection, attention, KV cache |

Scheduling rules:

- Latency mode: `queue_depth=1`, `concurrency=1`, dynamic batching disabled, no waiting for future requests.
- Throughput mode: static batching only within the provided batch tensor or manifest shape.
- LLM decode denominator is fixed by the contest. Generate 128 positions; after EOS, fill remaining positions with `eos_token_id`; do not report fewer generated positions to inflate tokens/s.
- LLM next-token argmax must run on device; return generated token IDs for decode. CPU may read final outputs for official scoring, but not compute next-token argmax.
- In batched decode, EOS masking is per sequence: sequences that hit EOS are padded with EOS through position 128 while unfinished sequences continue.
- The PyTorch wrapper should log mode, queue depth, batch policy, EOS handling, reset events, and fallback status.
- Main compute in scoreable models must log `fallback=false`; any debug-only fallback path must be clearly disabled or outside formal scoring. Legal CPU preprocessing still logs the required audit fields so it is distinguishable from unauthorized fallback.

## Phase 8: Models

Public CNN sanity model:

- Input `float32` NCHW `[batch,3,64,64]`.
- Output logits `[batch,10]`.
- Conv/BN/ReLU stem, residual blocks, adaptive average pool, linear head.

Public tiny decoder sanity model:

- `token_ids [batch,seq_len]`, `attention_mask [batch,seq_len]`, `seq_len <= 128`.
- Output logits `[batch,seq_len,4096]`.
- 2 decoder blocks, hidden 128, 4 heads, MLP 256, learned position embeddings, final LM head.

Formal ResNet-50:

- torchvision ResNet-50 v1.5, ImageNet-1K validation.
- Input preprocessed FP32 NCHW `[batch,3,224,224]`.
- Batches: 1 latency, 16 and 64 throughput.
- Output `[batch,1000]` FP32 or FP16 logits.
- Accuracy gates: hidden Top-1 drop <= 1.5 percentage points, Top-5 drop <= 1.0 percentage point.

Formal LLM:

- Approximately 1B decoder-only Transformer, fixed checkpoint/tokenizer.
- Batch 1 and 4, prompt length 128 and 512, hidden 64-768.
- Generate exactly 128 tokens, greedy decoding, temperature 0.
- Argmax must run on device, tie chooses smallest token ID.
- KV cache in U280 HBM/DDR; CPU attention is forbidden.
- Gates: perplexity degradation <= 5%, greedy token match >= 95%, public layer NRMSE <= 3%.

## Phase 9: Energy and Open Bonus

Energy:

- Scoreable energy uses endpoint metrics: ResNet uses `images/J`; LLM uses `tokens/J`.
- Use board sensor logs from the formal timing window, not estimated RTL toggles alone.
- Optimize wasted dynamic power only after correctness is stable: clock-enable idle CUs, inactive SIMT lanes, unused scoreboard paths, and idle MMA/SFU blocks; reduce unnecessary HBM traffic; avoid over-wide always-active datapaths.
- Validate every gating change with reset, fault recovery, randomized SIMT, long-run stability, and timing tests.
- Treat thermal throttling, power-limit resets, or watchdog resets during a 30-minute run as stability failures. Prefer coarse clock-enable gating and data holding for idle CUs/MMA/SFU/SIMT lanes over over-wide always-toggling datapaths.

Open bonus:

- Do not write bonus feature code before the baseline 25-point correctness tests and ResNet/LLM accuracy gates are fully passing. Open bonus cannot compensate for basic correctness, FP8/SFU, runtime legality, or E2E model failures.
- First consider compiler autotuning/automatic mapping, multi-kernel concurrency, async runtime pipeline, graph execution, or formal/fault-injection evidence. These usually add score evidence with less RTL disruption.
- Treat sparse GEMM, compressed memory, attention/KV cache special hardware, and training/backpropagation as higher-risk additions that require separate manifests and hidden-test-safe fallbacks.
- Every claimed bonus needs an `open_bonus_manifest`, tests, logs, and reproducible commands.
