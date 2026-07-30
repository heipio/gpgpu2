# Full Project Contract Audit

Date: 2026-07-29

Source of truth: `D:/桌面/contest.md`, `aec_g_isa_v1.json`, and the current repository.

## Current Position

The project is now past RTL bring-up and into Vitis/XDMA integration readiness. The current tree contains:

- A machine-readable AEC-G v1.0 ISA contract.
- Golden simulator, assembler, restricted PTX compiler, Python simulation runtime, fixed C runtime skeleton, PyTorch adapter skeleton.
- Synthesizable SystemVerilog RTL for CU front end, VRF/PRF, ALU/FPU/SFU/MMA integration, SIMT control, scoreboard, barrier, LSU, CSR, SoC wrapper, and four Vitis-visible AXI memory masters.
- IP-XACT and Vitis RTL kernel metadata.
- A regenerated formal RTL kernel object: `bitstream/aec_gpgpu.hw.xo`.

Mode classification: submission-readiness bring-up, but not full contest closure. The missing scoring artifact is still a routed `.xclbin` plus real-board correctness/performance/stability evidence.

## Contract Fixes Applied During This Audit

1. Branch target field correction.
   - `contest.md` 6.4.7 and 6.4.11 require `BR/BRX/SSY` target PCs in `src3_or_immext`, not `src2_or_imm32`.
   - Fixed `compiler/aec_assembler.py`.
   - Fixed PTX fixups in `compiler/compiler.py`.
   - Fixed golden execution in `tests/simulator.py`.
   - Fixed RTL branch target selection in `rtl/ex_stage.sv`.
   - Updated `rtl/tb_divergent_brx_system.sv` hand-written instruction constants.
   - Added `tests/test_contract_audit.py::test_branch_targets_use_src3_or_immext_contract_field`.

2. Test contract cleanup.
   - Updated stale assembler expected hex values to official opcode/type/pred layout.
   - Corrected MMA `pred_ctrl` expectation: `type=0xb` lives in `pred_ctrl[6:3]`, so base encoding is `0x0058`.
   - Added a `__main__` self-test entry to `tests/test_assembler.py`.
   - Regenerated `tests/vector_add.*`, `tests/alu_simt.*`, `tests/sfu_test.*`, and `tests/predicate_test.*`.

3. Packaging hygiene cleanup.
   - Removed stale generated `platform/ip_repo/aec_gpgpu_1_0/src/aec_soc_top.sv`.
   - Current packaged top is `aec_soc_top.v` wrapping `aec_soc_core.sv`.
   - Regenerated the current `.xo`; archive inspection confirms no stale `aec_soc_top.sv` remains.

## Verified Working Surface

Local Python self-tests:

```text
python tests/test_sim.py
python tests/test_compiler.py
python tests/test_assembler.py
python tests/test_contract_audit.py
```

All passed.

Remote Python 3.6.8 validation on `contest5@127.0.0.1:2222`:

```text
python3 tests/test_sim.py
python3 tests/test_compiler.py
python3 tests/test_assembler.py
python3 tests/test_contract_audit.py
```

All passed.

Remote Vivado/Vitis 2023.1 validation with XRT 2022.1 environment:

```text
make -C platform check-kernel
make -C platform ipxact
make -C platform xo
vivado -mode batch -source rtl/synth_soc_top_ooc.tcl
```

Results:

- `check-kernel`: passed, 28 packaged RTL sources present.
- `ipxact`: passed, generated `platform/ip_repo/aec_gpgpu_1_0/component.xml`.
- `xo`: passed, regenerated `bitstream/aec_gpgpu.hw.xo`, size `90305` bytes.
- SoC OOC synth: passed, no errors, no critical warnings.
- Timing at 5.000 ns: WNS `+0.339 ns`, TNS `0.000 ns`.

Target IP packager warnings closed:

- `IP_Flow 19-5101`: absent.
- `IP_Flow 19-3158`: absent.
- `IP_Flow 19-5661`: absent.
- `IP_Flow 19-11770`: absent.

Remaining warning class:

- SoC OOC synth still emits Xilinx Floating-Point IP internal unused-port warnings and a moved-XCI warning. These are not AEC-G semantic violations, but should be documented in the third-party IP/license/build notes before final submission.

## Stage Consistency Status

- Stage 1, ISA/golden model: structurally consistent. FP8 E4M3FN, SFU relative-error gates, MMA layout, inactive-lane reduction rule, predicate layout, CSR/fault map are represented in JSON and tested at golden-model level.
- Stage 2, software stack foundation: compiler/assembler/runtime skeleton exist and now agree on opcode, pred_ctrl, special register, memory-space, MMA alignment, and branch target fields.
- Stage 3-6, RTL bring-up/host control: CU pipeline, VRF/PRF, ALU, LSU, SIMT, CSR, XPM IMEM, scoreboard/barrier/FENCE hooks, and fault status are implemented to bring-up depth and pass OOC synthesis.
- Stage 7, assembler/runtime simulation: assembler and simulation runtime are usable; branch encoding was corrected during this audit.
- Stage 8, SFU: SFU model and RTL exist with documented relative-error thresholds; deeper randomized RTL-vs-golden sweeps remain needed for final confidence.
- Stage 9, MMA/FPU: FP8/MMA RTL integration exists and uses the Xilinx FMA IP path, but model-scale throughput and full bit-exact random RTL sweeps remain incomplete.
- Vitis/XDMA integration: IP-XACT and `.xo` are now generated. `.xclbin` link and real board run are still missing.

## Remaining Blocking Gaps To Full Contest Closure

1. Generate routed hardware `.xclbin`.
   - Run `v++ -l -t hw --platform xilinx_u280_gen3x16_xdma_1_202211_1 --config platform/connectivity.cfg`.
   - Inspect link timing/utilization/power and confirm all scoring clocks WNS >= 0.

2. Real-board XDMA/XRT execution.
   - Program U280 with the generated `.xclbin`.
   - Run the XRT host lifecycle: capability read, module load, kernel launch, synchronize, result readback, fault/counter read.
   - Capture `xbutil examine`, BDF, shell UUID, XRT, thermal/electrical logs.

3. Runtime completeness.
   - `runtime/aec_runtime.cpp` still has command queue, completion polling, cache flush/invalidate, and state-reset TODOs.
   - The scoreable path must reject unsupported capabilities and must not truncate 64-bit device pointers.

4. Memory subsystem performance.
   - The top exposes four HBM AXI masters, but the CU currently has one in-order LSU stream routed by address bits.
   - Full HBM throughput still needs multi-issue LSU queues, multiple CUs, or independent request streams.

5. Numeric and hidden-test confidence.
   - Expand SFU, FPU, MMA, SHFL, REDUCE, predicate, fault, and barrier randomized RTL-vs-golden differential tests.
   - Confirm MMA scale ABI and model manifest behavior for tensor/block/channel scale modes.

6. PyTorch/model scoring.
   - Build scoreable P0/P1 operators backed by the runtime.
   - Add ResNet-18/ResNet-50 and approximately 1B decoder-only Transformer paths.
   - Ensure CPU fallback logs are complete and fallback ratio is zero for scoreable main compute.

7. Submission evidence.
   - Add final timing/utilization/power reports, third-party IP/license list, benchmark raw logs, reproducibility commands, 30-minute stability evidence, and final audit manifest.

## Bottom Line

The stack is internally more consistent after this audit, and one real encoding bug was fixed across software, simulator, RTL, and tests. The current deliverable is a valid `.xo` plus synthesized SoC RTL foundation. It is not yet a complete contest submission until `.xclbin` link, board execution, scoreable runtime/PyTorch paths, model workloads, and stability evidence are closed.
