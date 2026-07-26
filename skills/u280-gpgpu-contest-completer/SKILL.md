---
name: u280-gpgpu-contest-completer
description: Complete, review, debug, optimize, or package the U280-GPGPU research contest entry described by contest.md. Use this skill whenever the user mentions U280, AEC-G, AEC runtime, PTX-to-AEC, GPGPU RTL, FP8 GEMM, SIMT, XDMA, ResNet/Transformer scoring, bitstream/xclbin submission, contest.md, or asks for a plan to finish this FPGA GPGPU contest, even if they only ask about one subsystem.
---

# U280-GPGPU Contest Completer

Use this skill to drive an end-to-end contest submission for the U280-GPGPU research competition. The job is not to build a toy GPU. The job is to produce a complete, auditable software-and-hardware system that obeys the fixed AEC-G ISA boundary, fixed CUDA-like runtime API boundary, U280 XDMA platform constraints, and the scoring rules.

## First Move

1. Read the local contest statement if the user provides it. If not, use the bundled references in this skill.
2. Inspect the repository before proposing architecture: identify `rtl/`, `runtime/`, `compiler/`, `pytorch/`, `tests/`, `reports/`, existing scripts, and any current bitstream or simulator.
3. Run the audit script early:

```bash
python skills/u280-gpgpu-contest-completer/scripts/audit_submission.py <repo-root>
```

4. Classify the current state into one of these modes:
   - `architecture`: no coherent design exists yet.
   - `implementation`: subsystem skeletons exist but are incomplete.
   - `debug`: tests or synthesis are failing.
   - `optimization`: correctness passes and PPA/throughput is the main work.
   - `submission`: packaging, logs, manifests, and reproducibility are the main work.

## Load References As Needed

- Read `references/contest-contract.md` when deciding whether a design is legal, complete, or scoreable.
- Read `references/implementation-roadmap.md` when planning or implementing subsystem work.
- Read `references/verification-and-scoring.md` when creating tests, interpreting results, or preparing final evidence.
- Read `references/u280-local-runbook.md` when the task involves remote access, local U280 board bring-up, `xbutil`, Vitis/XRT commands, `connectivity.cfg`, sw/hw emulation, xclbin loading, or collecting local board evidence.

Keep the official contest statement as the source of truth if it is available. The bundled references are a distilled operating contract.

## Non-Negotiable Contract

Treat these as hard boundaries:

- AEC-G v1.0 is the fixed software/hardware interface. Do not redefine opcode, register semantics, predicate/active-mask behavior, MMA fragment layout, address spaces, error codes, `.aecbin` layout, or ABI to fit a model.
- AEC runtime is the fixed PyTorch/application/device interface. PyTorch code, benchmark scripts, module load, memory copies, kernel launch, sync, errors, and counters must go through the fixed CUDA-like runtime API.
- Hardware may use microcode, dedicated MMA/SFU/reduction engines, private control signals, DMA engines, prefetchers, caches, or scratchpads, but their inputs, outputs, addresses, shapes, synchronization, and visible behavior must be driven by AEC programs, AEC ABI descriptors, or fixed runtime calls.
- CPU may do orchestration, metadata, DMA setup, loading, logging, and official scoring post-processing. CPU must not do input/weight-dependent model math in scoring windows.
- Hidden tests can generate unknown AEC/PTX kernels after the contest. A design that only handles public model names, shapes, fingerprints, or precompiled machine code is invalid.
- Board evidence matters. Simulation estimates and theoretical TOPS do not replace routed timing, board correctness, end-to-end timing, logs, and stability.
- Environment lock matters. All generated code, RTL, build scripts, containers, and documentation must target the official stack: CentOS 7.9, GLIBC 2.17, Vivado/Vitis 2022.2, XRT 2.13.479, and U280 Gen3x16 XDMA base_1. Default to conservative C/C++ and build-system features compatible with the official image; use C++17/C++20, newer GCC assumptions, newer Vivado Tcl/IP options, or newer XRT APIs only after the official devtoolset or SDK explicitly confirms support.
- Local runbooks are operational aids, not contest-law overrides. If local board notes mention Vitis/Vivado 2023.1, devtoolset-9, FRP/P2P, BDFs, or helper scripts, use them only for local development and mark the version mismatch risk; final submission evidence must still prove compatibility with the official contest environment.
- Never write credentials into the skill, repository, logs, docs, build scripts, or submission. Use remote usernames, passwords, SSH keys, FRP tokens, and secret keys only from the current user/session context, and redact them from copied command transcripts.
- Numeric thresholds are hard gates, not tuning suggestions. FP8 must implement required E4M3FN with round-to-nearest-even, canonical NaN, and overflow saturation to signed max finite value 448. E5M2 is optional; if implemented, it must follow the IEEE-like E5M2 rules and be declared in capability. SFU `RCP.f32` must meet max relative error <= 2^-10; `EXP2.f32` must meet max relative error <= 2^-9 in the normal result range; optional `RSQRT.f32` must meet max relative error <= 2^-9. LLM gates include perplexity degradation <= 5%, greedy token match >= 95%, and public layer NRMSE <= 3%.
- Strict floating-point order is part of correctness. Floating-point addition is not associative: `MMA.m16n16k16.e4m3.f32` must accumulate exactly in `k=0..15` order using FP32 FMA, and `REDUCE.ADD.f32` must follow the golden balanced binary tree over ascending logical lane IDs with steps 1, 2, 4, and so on.
- Floating-point edge behavior must match the manifest and golden simulator. Canonicalize NaN outputs unless an instruction explicitly preserves payload, declare subnormal handling such as flush-to-zero versus full subnormal support, and implement `MAD.f32` as multiply-rounded-then-add-rounded rather than silently mapping it to single-rounding `FMA.f32`.
- Inactive lanes are architecturally silent. Any lane masked off by active mask or predicate must not modify GPRs, predicates, memory, counters, or exception state; enforce write-enable masking on `SETP`, `CMPP`, `LD/ST`, SFU, MMA, and reduction writeback paths.
- Register alignment and base memory width are fixed. 64-bit scalar values and `.b64` load/store use even-aligned register pairs `{Rk+1, Rk}`. MMA A/B fragment starts must be even-aligned; C/D fragment starts must be 8-register aligned. Base AEC-G v1.0 does not support `.b128` single-instruction load/store.
- Address translation is required. Runtime APIs expose 64-bit device pointers, but base AEC-G `LD/ST` instructions use 32-bit address registers. Implement a base-register table, buffer table, or address-window mechanism that translates visible 32-bit ISA addresses into 64-bit HBM/DDR physical addresses; never truncate 64-bit pointers.
- Capability checks are part of legality. Hardware must expose read-only capability registers for warp width, lanes, numeric modes, memory features, optional ISA extensions, and resource limits. Runtime must compare these against the `.aecbin` manifest before module load/launch and return `AEC_ERROR_UNSUPPORTED_FEATURE` for unsupported requirements.
- State isolation is a scoring boundary. Retain only allowed persistent state such as bitstream, weights, compiled kernels, and input-independent autotune data. Clear input-related activations, intermediate buffers, output caches, lookup/hash caches, and LLM KV cache between requests, shapes, models, public/hidden phases, and post-warm-up measurement.
- Memory errors must be explicit. DMA and device caches need defined consistency via `FENCE`, launch-boundary flush/invalidate, or uncached windows. Unsupported unaligned accesses must trap with `MISALIGNED_ACCESS` or be correctly split; silent data corruption is never acceptable.
- Memory ordering must cover the baseline subops. Hardware must implement `FENCE` with `subop=0` for CTA scope and `subop=1` for DEVICE scope. If device caches are not coherent with XDMA, runtime must flush/invalidate at kernel launch, copy, and synchronization boundaries.

## Required Deliverable Surface

Expect the repository to converge toward this structure:

```text
rtl/                 # synthesizable RTL and auditable IP configuration
constraints/         # clocks, pins, pblock/SLR constraints
platform/            # U280 XDMA integration scripts
driver/              # XDMA driver or user-mode control path
runtime/             # fixed CUDA-like AEC runtime API and implementation
compiler/            # PTX-to-AEC compiler, assembler, disassembler, reports
pytorch/             # optimized PyTorch ops and E2E scheduling scripts
tests/               # ISA, random, model, board, and regression tests
bitstream/           # target xclbin/bitstream
reports/             # utilization, timing, power, benchmark, traces
docs/                # architecture, ABI, ISA extensions, reproduction docs
design.json          # machine-readable summary; MUST include CU count, logical_warp_width, physical_simd_lanes, issue_beats_per_warp, cache sizes, GEMM tiles, frequency, numeric modes, runtime capability, and driver version
```

If a directory is intentionally absent, require a documented equivalent and make sure scoring scripts can find it.

## Architecture Guidance

Start conservative and evidence-driven:

- Prefer a 2 CU bring-up path, then 4 CU reference scale, then targeted expansion only after routed timing and board tests.
- Preserve `logical_warp_width=32` semantics even when `physical_simd_lanes` is 4, 8, or 16. `%laneid`, active mask, predicate bits, shuffle, reduction, and MMA fragment layout are logical-lane concepts, not physical-lane concepts.
- Implement cross-beat warp operations when `physical_simd_lanes < logical_warp_width`. `SHFL` and `REDUCE` must see the entire logical warp, including lanes issued in previous or later beats; add a warp-level buffer, bypass network, or replay path so beat 0 can read beat 3 data correctly.
- Keep `issue_beats_per_warp = logical_warp_width / physical_simd_lanes`, and require exact divisibility.
- Favor a minimum viable scoreable system over a wide speculative design: scalar ISA, SIMT control, memory path, FP8 GEMM, SFU RCP/EXP2, runtime, compiler, and public E2E path must all close.
- Budget for U280 routing pressure with numbers, not hope. Keep the starter design near the conservative envelope: about 350K-450K LUT, 350-550 BRAM36, 120-200 URAM, 800-1,200 DSP. Baseline frequency is 180 MHz, target performance is 200-225 MHz, and 250 MHz is an advanced optimization goal. Watch the official reference ceilings of roughly 50% dynamic-region LUT/register/BRAM/URAM/DSP and about 55% DSP per SLR. Review utilization per SLR after every major RTL change.
- Pipeline cross-SLR paths deliberately. Insert register slices/pipeline stages on cross-SLR AXI, HBM, command, scoreboard, broadcast, reduction, and wide GEMM/control paths; avoid letting one long combinational path decide WNS.
- Treat U280 memory as heterogeneous. Use the 8 GB HBM2 as the high-bandwidth working set for hot activations, KV cache, frequently used weights, command buffers, and core tensor tiles; use 32 GB DDR4 as a second-level capacity pool for cold weights, datasets, overflow, or staging when model size grows. Runtime and PyTorch placement policies should expose and log HBM/DDR choices.
- Report HBM/DDR access mapping and bandwidth honestly. At least 4 independent HBM pseudo-channels are required; 8-16 HBM ports are the reference performance target, and DDR4 traffic must not be hidden when used.
- Implement SFU with FPGA-sensible microarchitecture first. Prefer BRAM/URAM/distributed-ROM LUTs plus range reduction, linear interpolation, low-order polynomial refinement, or one Newton-Raphson step for RCP/EXP2/RSQRT; avoid huge unpipelined combinational approximations or DSP-heavy Taylor expansions unless resource/timing reports prove they close.
- If an SFU is shared across CUs or warps, add explicit arbitration, ready/valid back-pressure, and request tags carrying CU, warp, lane mask, destination register, and instruction identity. Variable-latency or out-of-order completions must write back only to the matching in-flight request.
- Respect the U280 power and thermal envelope. Use measured board power during long runs, add safe clock-enable or coarse-grain gating for idle CUs/MMA/SFU/SIMT lanes, and treat thermal or power-limit resets as stability failures, not as tunable noise.

## Implementation Workflow

1. **Contract Audit**
   - Inventory missing deliverables and hard rule violations.
   - Check current ISA, runtime API, CPU fallback, hidden-test portability assumptions, and official environment compatibility.
   - Flag dependencies on unsupported GLIBC, compiler language standard, Vivado/Vitis version, XRT API, kernel version, or shell/platform.
   - Produce a short gap list ordered by scoring risk.

2. **Golden Model First**
   - Build or verify an AEC-G instruction-level simulator before deep RTL work.
   - Use it as the shared reference for assembler, compiler, RTL traces, FP8 conversion, MMA layout, SFU approximation, and error behavior.
   - Encode FP8, SFU, MMA, and model accuracy thresholds directly in golden-model tests and RTL testbenches so numerical drift fails early.
   - Keep machine-readable ISA/capability data in versioned JSON.

3. **Compiler/Assembler Path**
   - Implement PTX 9.3 restricted-subset parsing from PTX to AEC-G.
   - Include CFG, type checks, lowering, register/predicate allocation, branch target fixups, `.aecbin` emission, manifest emission, disassembly, and compile reports.
   - Emit `.aecbin` as strict 128-bit fixed-width instructions: exactly four 32-bit little-endian words per instruction, no file header.
   - Lower PTX 128-bit/vector memory operations into multiple 32/64-bit AEC `LD/ST` instructions unless the hardware explicitly declares a compatible vector-memory capability; base AEC-G v1.0 `.b128` load/store is illegal.
   - Map manifest `dynamic_smem_bytes` into the kernel ABI and launch descriptor. Resolve the dynamic shared-memory base at launch and prove `.smem` accesses cannot overflow the per-CU BRAM/URAM allocation or collide with static shared memory.
   - Enforce register alignment in compiler diagnostics: 64-bit values and `.b64` memory operations use even register pairs, MMA A/B fragments start on even registers, and MMA C/D fragments start on 8-register boundaries.
   - Keep PTX-to-AEC lowering general. Do not replace kernels by name, shape, hash, model layer, or manifest fingerprint with hardcoded binaries; hidden unknown-kernel portability is a scored requirement.
   - Allow `nvcc` only for `.cu` to PTX. The PTX-to-AEC path must be self-authored and source-submitted.

4. **RTL Bring-Up**
   - Bring up fetch/decode, GPR/predicate state, warp PC, active mask, branch/reconvergence, scoreboard, load/store, command queue, and completion first.
   - Implement SIMT divergence precisely: divergent `BRX` must execute both taken and fall-through paths under the correct active masks. `SSY` and `SYNC` must push/pop reconvergence PCs and masks, and stack overflow/underflow must raise `SIMT_STACK_FAULT`.
   - Implement dynamic barriers precisely: `BAR.SYNC` with `expected_warps=0` synchronizes all currently non-halted warps in the block, so hardware must track active warp count per block rather than using a fixed launch-time constant.
   - Implement cross-beat `SHFL` and `REDUCE` before trusting partial-width SIMD results; tests must cover source lanes in different issue beats.
   - Add FP8 MMA and SFU after scalar/memory/SIMT traces match the simulator.
   - Match floating-point semantics exactly: MMA FP8 accumulates in `k=0..15` order with FP32 FMA, `REDUCE.ADD.f32` uses the specified logical-lane balanced binary tree, `MAD.f32` keeps double-rounding behavior, and SFU special values are explicitly tested.
   - Require fault reporting: illegal instruction, misaligned access, address error, SIMT stack fault, barrier deadlock, watchdog timeout, fault PC, CU/warp/block ID.
   - Define whether unaligned memory accesses are split or rejected; implement the same behavior in compiler diagnostics, RTL, simulator, and tests.

5. **Runtime/XDMA**
   - Implement the fixed `aec_runtime.h` semantics: context, malloc/free, H2D/D2H, module load, kernel launch, synchronize, last error, counters.
   - Validate `.aecbin`, manifest, resources, and capability before launch.
   - Implement a 64-bit-to-32-bit address-window contract: map runtime device pointers to buffer IDs, base-register entries, or window selectors consumed by AEC kernels, and reject launches whose pointer/window metadata cannot be represented safely.
   - Validate device capability registers against the manifest and return `AEC_ERROR_UNSUPPORTED_FEATURE` for unsupported warp width, numeric mode, vector memory, shared memory, or optional ISA requirements.
   - Map `dynamic_smem_bytes` into launch metadata and reject launches exceeding per-CU shared-memory capacity.
   - Implement explicit HBM/DDR allocation and placement policy: hot tensors and KV cache default to HBM; cold weights, large datasets, overflow, or staging may use DDR4. Record placement, migration, and traffic counters.
   - Implement explicit state-management hooks for request/shape/model/phase transitions and after warm-up: clear input-related buffers, output caches, intermediate activations, lookup/hash tables, and LLM KV cache while retaining allowed weights, bitstream, compiled kernels, and input-independent autotune state. Warm-up inputs must not be reused as hidden scoring inputs.
   - Ensure DMA/cache consistency through `FENCE` `subop=0` CTA, `subop=1` DEVICE, runtime flush/invalidate, or uncached windows at launch/copy/sync boundaries.
   - Log H2D, kernel, D2H, counters, fallback state, state-reset events, timeout/reset events, and cache flush/invalidate boundaries.

6. **PyTorch and Models**
   - Build a PyTorch package around explicit device buffer and runtime calls.
   - Prioritize P0/P1 ops: copy, elementwise add/mul, ReLU, FP8 GEMM/linear, Conv2d lowering, bias, pooling, residual.
   - Then add P2/P3 paths: LayerNorm/RMSNorm, Softmax, GELU/SiLU, transpose/reshape, batched GEMM, QKV, attention, KV cache.
   - Ensure every operator discloses fallback with exact audit fields: `fallback=false/true`, fallback reason, CPU time, input/output bytes, call count, and operator/model name. Use `fallback=false` for all scoreable main compute; missing fields make legal CPU work look unauthorized.
   - Use the CPU whitelist aggressively but legally: do layout transformation, byte packing, padding, tensor blocking, shape/stride metadata, pinned-memory setup, and DMA descriptor generation before H2D when it simplifies RTL or improves bandwidth.
   - Do not do CPU-side input/weight-dependent math: no convolution, GEMM, attention, normalization, activation, reduction, argmax, dynamic quant/dequant, scale estimation, KV update, logits calculation, or hidden-output lookup.
   - For LLM decode, compute argmax on the FPGA and return generated token IDs, not full logits for CPU argmax. Tie-breaking must select the smallest token ID.
   - Enforce the LLM EOS rule in batched decoding: after a sequence emits `eos_token_id`, fill all remaining output positions up to `max_new_tokens=128` with `eos_token_id` while other batch elements continue correctly.
   - Expose per-request state-reset and KV-cache clearing in the PyTorch wrapper so public and hidden prompts cannot contaminate each other.

7. **Verification Ladder**
   - Unit test every opcode, predicate case, branch path, memory width, fault, FP8 conversion, MMA fragment lane, SFU special value, and runtime API.
   - Assert E4M3FN RNE/saturation/canonical-NaN behavior, `RCP` <= 2^-10 max relative error, `EXP2` <= 2^-9 max relative error, optional `RSQRT` <= 2^-9, CNN Top-1/Top-5 gates, LLM perplexity <= 5% degradation, token match >= 95%, and NRMSE <= 3%.
   - Assert SFU special values: `RCP(+/-0) -> +/-Inf`, `RCP(+/-Inf) -> +/-0`, `EXP2` overflow -> `+Inf`, `EXP2` underflow -> `+0`, `RSQRT(+0) -> +Inf`, and `RSQRT(negative) -> canonical NaN` if RSQRT is implemented.
   - Add inactive-lane tests proving masked lanes cannot modify registers, predicates, memory, or exceptions.
   - Add tests that switch prompts, shapes, models, and public/hidden-style phases while asserting KV cache, activation buffers, output buffers, and input-derived caches are cleared.
   - Test unaligned access behavior, `MISALIGNED_ACCESS` fault paths, DMA/cache visibility, `FENCE`, and runtime flush/invalidate boundaries.
   - Add resource and floorplan checks: per-SLR LUT/BRAM/URAM/DSP usage, cross-SLR pipeline/register-slice presence, timing path reports, HBM/DDR bandwidth counters, and SFU LUT/interpolation error sweeps.
   - Add randomized instruction and random shape tests.
   - Use differential tests: PTX/kernel intent -> compiler -> AEC simulator -> RTL sim -> board.
   - Run public CNN/Transformer sanity models before full ResNet/LLM optimization.

8. **PPA and Scoring Optimization**
   - Optimize after correctness gates pass.
   - Prioritize by scoring weights: the approximately 1B decoder-only LLM is 18 points and ResNet-50 is 12 points, ahead of ResNet-18 at 4 points. Focus first on LLM prefill/decode/E2E tokens/s and ResNet-50 batch throughput after their accuracy gates pass.
   - Use weighted geometric means and end-to-end timing, not single-kernel vanity metrics.
   - Improve the bottleneck shown by traces: HBM bank conflicts, launch overhead, GEMM occupancy, SFU/reduction latency, layout conversion, D2H/H2D, or routing frequency.
   - Keep latency and throughput schedulers separate. For latency metrics enforce `queue_depth=1`, `concurrency=1`, and dynamic batching disabled. For throughput metrics, use only static batching inside the provided manifest batch size.
   - Do not inflate LLM throughput by waiting for future requests, returning full logits for CPU argmax, ignoring EOS fill rules, early-stopping the denominator, or reporting only successful rounds. The generation denominator remains `batch * 128`.
   - Track energy as a score, not an afterthought. Use board power logs to optimize `images/J` and `tokens/J`; add verified clock-enable or coarse-grain gating for idle CUs, inactive SIMT lanes, and idle MMA/SFU blocks when it does not endanger timing, reset, or functional correctness.

9. **Open Bonus Strategy**
   - Do not write Open Bonus feature code until the baseline 25-point correctness tests and ResNet/LLM accuracy gates are fully passing. Bonus points cannot rescue a design that fails basic correctness, FP8/SFU gates, runtime legality, or E2E model gates.
   - Prefer lower-RTL-risk bonuses first: compiler autotuning/automatic mapping, multi-kernel concurrency, async runtime pipelines, graph execution, or formal/fault-injection evidence.
   - Treat sparse GEMM, compressed memory, attention/KV-cache hardware, and training support as higher-risk work that needs its own manifest, tests, and board evidence.

10. **Submission Closure**
   - Produce bitstream/xclbin, reports, logs, benchmark raw data, design docs, `design.json`, third-party IP/license list, and one-click or staged build scripts such as Makefiles, CMake presets, or bash scripts for full reproduction.
   - Verify zero timing violations: WNS must be >= 0 on all scoring clocks. Do not submit a bitstream just because it appears to run on the board with WNS < 0; lower frequency or pipeline until timing closes.
   - Run at least 30 minutes continuous stability with board power/thermal logs and no thermal, power-limit, watchdog, or reset events.
   - Re-run the audit script and resolve all critical warnings or explicitly document accepted risks.

## Answer Style When Using This Skill

- Be concrete. Name files, tests, manifests, scripts, and next commands.
- Separate legality/correctness risks from performance ideas.
- When reviewing code, lead with scoring-blocking defects and hidden-test failures.
- When designing, explain how each subsystem satisfies the fixed ISA/runtime boundary.
- When optimizing, tie every change to a scoring formula, threshold, trace, or measured bottleneck.
- Avoid suggesting CPU shortcuts, model-name dispatch, shape fingerprinting, or hardwired network execution.

## If Information Is Missing

Ask the user for only the file or evidence needed to proceed, such as:

- Current repository path if it is not the workspace root.
- Existing ISA JSON, runtime header, manifest schema, or scoring SDK.
- Failing test logs, Vivado timing/utilization reports, board traces, or runtime counters.
- Public model files, weights, or benchmark manifests if model work is requested.

If the user asks for a complete plan and no codebase exists, produce a staged architecture and deliverable checklist rather than pretending implementation details are known.
