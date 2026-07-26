# Verification and Scoring

Use this reference when writing tests, interpreting logs, or preparing final submission evidence.

## Verification Ladder

1. ISA unit tests
   - Every opcode.
   - Predicate enable/disable/negation.
   - Active-mask effects.
   - Inactive lanes cannot update GPRs, predicates, memory, counters, or exception state.
   - Reserved opcode/type/space rejection.
   - Special registers: `%tid`, `%ctaid`, `%laneid`, `%warpid`, `%clock_lo`.
   - 32-bit/64-bit register-pair rules.
   - 64-bit even register-pair alignment and `.b64` load/store pair legality.
   - MMA A/B even alignment and C/D 8-register alignment.
   - Base ISA rejection of `.b128` load/store unless vector-memory capability is declared.

2. SIMT tests
   - Multi-warp residency and switching.
   - Branch divergence and reconvergence, including divergent `BRX` tests proving both taken and fall-through paths execute under correct active masks.
   - `SSY/SYNC` stack overflow/underflow.
   - `SIMT_STACK_FAULT` fault PC/CU/warp/block metadata.
   - `HALT` per logical thread and warp/block completion.
   - `BAR.SYNC` normal cases and timeout/deadlock handling.
   - `BAR.SYNC expected_warps=0` dynamic active-warp count, including halted-warps-before-barrier cases.
   - Cross-issue-beat shuffle and reduction over logical lanes 0..31.
   - Cross-beat `SHFL` where a lane in beat 0 reads a source lane in beat 3, and cross-beat `REDUCE` over all 32 logical lanes with partial-width physical SIMD.

3. Memory tests
   - `.pmem`, `.smem`, `.gmem`.
   - 8/16/32/64-bit load/store.
   - 64-bit runtime device pointer to 32-bit ISA address-window translation; include buffers above the 4 GB boundary to prove pointers are not truncated.
   - Natural alignment, correctly split unaligned access or explicit `MISALIGNED_ACCESS`, out-of-bounds faults.
   - DMA/cache flush/invalidate visibility, stale-line invalidation, `FENCE.CTA`, `FENCE.DEVICE`, and raw `FENCE subop=0/1` decode behavior.
   - HBM bank mapping, bandwidth, conflict patterns.
   - HBM/DDR placement tests for hot tensors, cold weights, overflow/staging buffers, and placement logs.
   - Atomics: at least `ATOM.ADD.u32`.
   - `FENCE` CTA and DEVICE.

4. Numeric tests
   - FP32 ADD/SUB/MUL/MAD/FMA, including MAD double-rounding vs FMA fused behavior. Add cancellation and tie cases that fail if MAD is mapped to fused FMA.
   - FP16/BF16 conversions.
   - E4M3FN conversions: signed zero, subnormal, normal, max finite 448, saturation, canonical NaN.
   - Declared subnormal behavior, such as flush-to-zero or full subnormal support, matches manifest/capability and RTL for every numeric path.
   - Round-to-nearest-even tie cases for FP8, FP16, BF16, and FP32 conversions.
   - Assert E4M3FN overflow saturation to signed max finite 448 and NaN canonicalization.
   - Canonical NaN outputs unless payload preservation is explicitly specified.
   - Optional E5M2 only when capability declares it.
   - PACK/UNPACK register groups and illegal group bounds.
   - MMA layout per logical lane, full-warp requirement, scale indexing, k-order accumulation.
   - MMA strict `k=0..15` FP32 FMA accumulation order.
   - `REDUCE.ADD.f32` balanced binary tree over ascending logical lanes with steps 1, 2, 4, and so on.
   - SFU special values, domains, relative error, P99 error, latency, initiation interval.
   - SFU exact special mappings: `RCP(+/-0) -> +/-Inf`, `RCP(+/-Inf) -> +/-0`, `EXP2` overflow -> `+Inf`, `EXP2` underflow -> `+0`, optional `RSQRT(+0) -> +Inf`, and optional `RSQRT(negative) -> canonical NaN`.
   - Assert `RCP.f32` max relative error <= 2^-10, `EXP2.f32` max relative error <= 2^-9 in normal result range, and optional `RSQRT.f32` max relative error <= 2^-9.

5. Compiler tests
   - PTX parse diagnostics.
   - CFG and branch targets.
   - Register/predicate allocation.
   - 64-bit pointer ABI.
   - `.aecbin` byte layout.
   - Strict 128-bit instruction emission: four little-endian 32-bit words per instruction and no header.
   - PTX vector or 128-bit memory lowering into legal 32/64-bit AEC `LD/ST`, or capability-gated vector memory.
   - Register alignment diagnostics for 64-bit values and MMA fragments.
   - Compile report completeness.
   - Unknown kernel portability.
   - No kernel-name, shape-hash, layer-name, or model-fingerprint dispatch to hardcoded binaries.
   - Manifest `dynamic_smem_bytes` mapping, static/dynamic `.smem` layout, launch metadata, and overflow diagnostics.

6. Runtime tests
   - Context init and capability.
   - Malloc/free and address validity, including HBM/DDR buffers whose 64-bit device pointers differ above bit 32.
   - Address-window, base-register table, or buffer-table setup/teardown for every kernel launch.
   - H2D/D2H sizes, alignment, large chunking.
   - Module load manifest mismatch.
   - Capability-register versus manifest mismatch returns `AEC_ERROR_UNSUPPORTED_FEATURE`.
   - Launch resource mismatch.
   - `dynamic_smem_bytes` launch acceptance/rejection at the per-CU shared-memory boundary.
   - Synchronize and last-error behavior.
   - Counter reads and fault information.
   - Timeout/reset and recovery.

7. Model tests
   - Public CNN and public tiny decoder.
   - FP8 GEMM shapes, tail blocks, alignment, random values.
   - ResNet-18 and ResNet-50 E2E.
   - LLM prefill/decode/E2E, KV cache, on-device argmax, smallest-token tie break, and EOS fill behavior.
   - Batched LLM decode where different sequences hit EOS at different steps; ended sequences pad with `eos_token_id` through exactly 128 positions while unfinished sequences continue.
   - Alternating prompt, shape, model, and public/hidden-style phase tests that prove KV cache, activation scratch, output buffers, and input-derived caches are cleared.
   - Warm-up contamination tests that use distinct warm-up/scoring inputs and assert state clearing after warm-up before timing.
   - Latency-mode tests that assert `queue_depth=1`, `concurrency=1`, and dynamic batching disabled.
   - Throughput-mode tests that assert batching stays within the provided batch and EOS denominator rules are respected.
   - Random hidden-like shapes and boundary prompts.

8. Board/stability tests
   - Routed timing with WNS >= 0 on all scoring clocks; WNS < 0 is not acceptable even if a local board run appears to work.
   - Per-SLR utilization and timing-path review after implementation.
   - Cross-SLR register slice or pipeline evidence for AXI/HBM/control/reduction/wide datapaths.
   - 30-minute continuous run.
   - Temperature and power logs.
   - No thermal throttling, power-limit reset, watchdog reset, or unexplained board reset during the long run.
   - Board power logs from the same formal timing windows used for throughput.
   - P50/P95/max latency.
   - Repeated cold boot and bitstream load.

9. Environment tests
   - Build host/runtime/compiler code on the official or faithfully mirrored CentOS 7.9 and GLIBC 2.17 environment.
   - Run Vivado/Vitis 2022.2 scripts without newer Tcl/IP assumptions.
   - Link against XRT 2.13.479 APIs.
   - Record compiler, C++ standard, Python, package, container, shell UUID, and kernel versions.

10. SFU microarchitecture tests
   - LUT table initialization and fixed contents.
   - Range reduction and reconstruction boundary cases.
   - Linear interpolation or refinement accuracy sweeps.
   - Pipeline latency, initiation interval, back-pressure, and tag/writeback correctness.
   - Shared-SFU arbitration across multiple CUs/warps, request tagging, back-pressure, and out-of-order completion writeback to the correct CU/warp/lane/register.
   - Resource report for LUT, BRAM, URAM, DSP, and registers.

## End-to-End Timing Rules

Operator timing:

- Inputs, weights, and outputs are already resident on device.
- Timer starts when `aecKernelLaunch` is visible.
- Timer ends when kernel completion is visible and required device fence is complete.

Model timing:

- Timer starts when scorer gives a defined CPU Tensor or token batch to the backend.
- Timer ends when final logits or generated token IDs are synchronized to CPU-readable memory.
- Include layout conversion, quantization, H2D, all kernels, launch/sync overhead, D2H, and required device computation.
- Exclude JPEG decode, resize/crop, tokenizer, and one-time offline compilation unless the manifest says otherwise.
- Legal CPU-side layout transformation, tensor packing, padding, byte-level copying, pinned-memory setup, IOMMU mapping, and DMA descriptor generation may be included in model timing when they occur after scorer handoff. They are allowed only when they do not perform input/weight-dependent numerical compute.

Latency:

- Report P50, P95, max.
- P95 is the `ceil(0.95*N)` sample after sorting by latency.
- Use at least 100 requests or all requests in 30 seconds, whichever is larger.
- Formal latency uses `queue_depth=1` and `concurrency=1`.
- Disable dynamic batching and do not wait for future requests in latency mode.
- Keep latency scheduler code separately configurable from throughput mode so optimization changes cannot silently alter the scoring mode.

Throughput:

- Use static batching only inside the batch tensor or manifest-provided shape.
- Do not fabricate throughput by accumulating future requests, ignoring failed rounds, skipping synchronization, or changing the fixed output denominator.
- For LLM, generation throughput denominator is fixed by `batch * 128`; EOS positions after the first EOS must still be filled with `eos_token_id`.
- Do not stop the decode timing denominator early for samples that hit EOS. Mask completed sequences and continue producing padded positions through 128.

Warm-up and state:

- Use required warm-up counts only.
- Warm-up input must not be the hidden scoring input or any input that can leak hidden scoring state.
- Clear input-related activation, output, KV cache, hash table, lookup cache, and hidden-sample intermediate state between phases.
- Bitstream, weights, compiled AEC kernels, and legal input-independent autotune results may remain resident if logged.
- Clear input-derived state after warm-up before timed measurement, between public/hidden phases, between model switches, between shape switches, and between unrelated LLM prompts.
- Log state-reset events, including KV-cache clear, activation scratch clear, output buffer clear, and cache flush/invalidate.

## Formal Public Tasks

ResNet-50:

- Batch 1 latency, batch 16 and 64 throughput.
- Preprocessed FP32 NCHW `[batch,3,224,224]`.
- Output `[batch,1000]` logits, FP32 or FP16.
- Warm-up: 10 per batch.
- Formal run: at least 100 batches or 30 seconds, whichever is longer.
- Gates: hidden Top-1 drop <= 1.5 percentage points, Top-5 drop <= 1.0 percentage point.

LLM:

- Batch 1 and 4.
- Prompt lengths 128 and 512; hidden 64-768.
- Generate fixed 128 tokens.
- Greedy decode, temperature 0; argmax on device; ties choose smallest token ID. Returning full logits to CPU so the CPU chooses the next token is not scoreable decode.
- Output generated `[batch,128] int32 token_ids`.
- Perplexity path returns `[batch,seq,vocab]` logits or manifest-approved next-token logprob.
- Warm-up: 3 per shape.
- Formal run: at least 20 prompts per shape, 3 rounds, median.
- Gates: perplexity degradation <= 5%, token match >= 95%, public layer NRMSE <= 3%.
- KV cache belongs to a single request/sequence context. It must be initialized or cleared between prompts unless the official manifest defines a legal continuation.
- Hidden prompts may be ordered to expose stale KV cache, output-cache contamination, CPU argmax, wrong EOS padding, or early-stop denominator tricks.

Evaluation procedure:

1. Cold boot and load bitstream.
2. Query capability and validate features.
3. Load weights; record load time outside steady-state.
4. Run public correctness/boundary tests.
5. Run hidden accuracy tests.
6. Clear input-related state.
7. Warm up after accuracy gates.
8. Clear input-related state again.
9. Run throughput shapes in fixed random order.
10. Repeat clearing when switching model, shape, or public/hidden phase.
11. Run at least 30 minutes of stability.
12. Export runtime traces, temperature, resources, frequency, and raw timing.
13. Confirm timing reports show WNS >= 0 for every scoring clock in the submitted bitstream.

Throughput trials:

- Use 3-round median.
- If max/min differs by more than 5%, increase to 7 rounds and take median.
- Timeout/reset/error rounds count as throughput 0.
- Do not report only successful rounds.
- All async work must complete before stopping the timer.

## Scoring Summary

Total: 100 points plus up to 10 open bonus.

### 25 Points: Basic Correctness and Completeness

| Item | Points |
|---|---:|
| AEC scalar ISA, ABI, random instruction tests | 6 |
| SIMT divergence/reconvergence, sync, multi-warp correctness | 6 |
| HBM/DDR, DMA, cache, exception recovery | 5 |
| FP8 GEMM and SFU numeric correctness | 5 |
| Reproducible build, docs, automated tests | 3 |

Gate: below 15/25, failing FP8 GEMM, or failing all required E2E models prevents E2E ranking.

### 15 Points: Operator Performance

- FP8 GEMM: 7.
- Memory/reduction/normalization/activation/SFU: 5.
- Multi-shape geometric mean and tail robustness: 3.

Formula:

```text
score_i = weight_i * min(1, log(1 + perf_team/perf_base) / log(1 + perf_target/perf_base))
```

### 40 Points: E2E Model Performance and Reliability

| Item | Points |
|---|---:|
| ResNet-50 multi-batch E2E throughput | 12 |
| ~1B Transformer prefill/decode/E2E throughput | 18 |
| ResNet-18 multi-batch E2E throughput | 4 |
| Full-flow overhead including H2D/D2H, quant/layout, launch | 4 |
| Long-run P95 latency and stability | 2 |

Optimization priority after gates pass:

- First optimize the approximately 1B LLM path: 18 points, with prefill/decode/E2E tokens/s dominating the model score.
- Then optimize ResNet-50: 12 points, especially batch 16 and batch 64 throughput after Top-1/Top-5 gates pass.
- Then optimize ResNet-18: 4 points, useful for coverage and energy but lower impact than LLM and ResNet-50.
- Preserve gates while optimizing: LLM perplexity degradation <= 5%, token match >= 95%, public layer NRMSE <= 3%, and ResNet Top-1/Top-5 drop limits.

Weighted geometric means:

```text
T_model = exp(sum_i(weight_i * ln(max(T_i, epsilon))) / sum_i(weight_i))
```

Weights:

```text
ResNet-50: batch1=20%, batch16=40%, batch64=40%
ResNet-18: batch1=20%, batch16=40%, batch64=40%
LLM: prefill=30%, decode=50%, full E2E=20%
LLM internal batch/prompt-length shapes: equal-weight geometric mean
```

Normalized model scores:

```text
S_CNN = 12 * (T_CNN_team / T_CNN_best)^0.5
S_LLM = 18 * (T_LLM_team / T_LLM_best)^0.5
S_R18 = 4 * (T_R18_team / T_R18_best)^0.5
```

Accuracy gates dominate performance. If Top-1/Top-5, perplexity, token match, or NRMSE fails, the corresponding model performance score is 0.

### 12 Points: Software Stack and Programmability

| Item | Points |
|---|---:|
| PTX-to-AEC compiler correctness and optimization | 5 |
| PyTorch ops, E2E scheduling, fallback logs | 3 |
| XDMA/runtime async behavior, error handling, observability | 2 |
| Unknown-kernel portability and docs | 2 |

Formula:

```text
weighted_pass_rate = sum_i(weight_i * pass_i) / sum_i(weight_i)
```

### 8 Points: Energy Efficiency and Engineering Quality

| Item | Points |
|---|---:|
| Measured energy efficiency | 4 |
| Timing closure, long-run and thermal stability | 2 |
| Design clarity, coverage, resource efficiency | 2 |

Energy:

```text
Eff_R18 = T_R18 / P_avg_R18
Eff_R50 = T_R50 / P_avg_R50
Eff_LLM = T_LLM / P_avg_LLM

S_eff_R18 = 1 * min(1, (Eff_R18 / Eff_R18_ref)^0.5)
S_eff_R50 = 1 * min(1, (Eff_R50 / Eff_R50_ref)^0.5)
S_eff_LLM = 2 * min(1, (Eff_LLM / Eff_LLM_ref)^0.5)
```

Energy optimization guidance:

- Use measured board power in the same window as the throughput measurement.
- Reduce dynamic power by verified clock-enable or coarse-grain gating for idle CUs, inactive lanes, idle MMA/SFU, and unused memory pipelines.
- Reduce memory energy by improving locality, HBM bank balance, batching inside the manifest, and avoiding redundant layout conversions.
- Re-run timing, reset, fault recovery, random SIMT, and 30-minute stability after every power-oriented RTL change.

### Up To 10 Bonus Points

| Bonus | Cap |
|---|---:|
| Sparse GEMM, structured sparsity, compressed memory | 2 |
| Multi-kernel concurrency, async pipeline, graph execution | 2 |
| Attention/KV cache optimization | 2 |
| Training/backpropagation | 1 |
| Formal verification, fault injection, security isolation | 1 |
| Compiler autotuning, automatic mapping, architecture search | 2 |

Bonus cannot compensate for failing correctness gates. Do not implement or submit bonus feature code until baseline 25-point correctness tests and ResNet/LLM accuracy gates are already passing; otherwise the extra complexity is more likely to invalidate the base submission than improve the score.

Recommended bonus order after baseline scoring:

1. Compiler autotuning, automatic mapping, or architecture search: up to 2 points, often mostly compiler/runtime/test infrastructure.
2. Multi-kernel concurrency, async pipeline, or graph execution: up to 2 points, useful when runtime and command queues are already reliable.
3. Formal verification, fault injection, or safety isolation: up to 1 point, valuable for engineering-quality evidence.
4. Attention/KV-cache specialization: up to 2 points, valuable for LLM score but needs careful hidden-shape support.
5. Sparse GEMM/compressed memory and training/backpropagation: potentially useful, but higher RTL and verification risk.

## Evidence Checklist

Require:

- Final xclbin/bitstream for the specified U280 platform.
- Vivado utilization and timing summary with all scoring clocks WNS >= 0.
- Power/temperature logs.
- Runtime trace with H2D/kernel/D2H/counters/fault fields.
- Capability-register and manifest validation logs, including `AEC_ERROR_UNSUPPORTED_FEATURE` negative tests.
- HBM/DDR placement and traffic report, including hot/cold tensor policy and bank mapping.
- Address-window or buffer-table evidence proving 64-bit runtime pointers are translated to 32-bit ISA-visible addresses without truncation, including above-4 GB tests.
- Per-SLR utilization, pblock/floorplan, SLR crossing, and cross-SLR pipeline/register-slice evidence.
- SIMT divergence/barrier evidence: `BRX` both-path execution, `SSY/SYNC` reconvergence stack behavior, `SIMT_STACK_FAULT`, and `BAR.SYNC expected_warps=0` dynamic active-warp behavior.
- Cross-beat warp evidence for `SHFL` and `REDUCE` over all 32 logical lanes with partial-width physical SIMD.
- SFU microarchitecture evidence: LUT/interpolation/refinement method, latency, initiation interval, shared-SFU arbitration/tags, out-of-order writeback tests, error sweeps, and resources.
- Numeric edge evidence: MAD double-rounding versus FMA, canonical NaN, declared subnormal behavior, inactive-lane write masking, and SFU special-value mappings.
- State-reset log covering KV cache, activation scratch, output buffers, input-derived caches, and phase/model/shape transitions.
- Warm-up contamination evidence proving warm-up inputs differ from scoring inputs and input-derived state is cleared after warm-up.
- DMA/cache consistency evidence: `FENCE subop=0/1` behavior, runtime flush/invalidate logs, and unaligned-access split/fault tests.
- Latency/throughput scheduler evidence: queue depth, concurrency, dynamic batching flag, static batch policy, EOS denominator handling.
- LLM decode evidence: on-device argmax, smallest-token tie break, generated token IDs returned, and batch-wise EOS padding through 128 positions.
- CPU whitelist evidence showing layout/packing/padding/DMA preparation separated from banned numerical compute.
- Public and hidden-style test logs.
- Fallback logs showing main compute fallback ratio 0 for scored models.
- Fallback logs must include `fallback=false/true`, reason, CPU time, input bytes, output bytes, call count, and operator/model name for every operator, including legal CPU preprocessing.
- Compiler reports for kernels.
- PyTorch benchmark logs and raw timings.
- Stability test log for at least 30 minutes.
- `design.json`.
- One-click or staged build scripts such as Makefiles, CMake presets, or bash scripts, plus reproduction commands and tool versions.
- Dynamic shared-memory ABI evidence for `dynamic_smem_bytes`, static/dynamic `.smem` layout, and per-CU capacity rejection tests.
- License and third-party IP list.
- Open bonus evidence must include passing baseline correctness and ResNet/LLM accuracy logs captured before bonus features are enabled.
