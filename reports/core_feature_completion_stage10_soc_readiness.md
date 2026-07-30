# Stage 10 SoC Integration And Core Feature Readiness

Date: 2026-07-29

## Scope

This stage closed the current RTL feature surface needed before Vitis/XDMA platform integration:

- MMA scoreboard dependency tracking was expanded from a single destination register to fragment ranges.
- Barrier synchronization was namespaced by block to prevent same-barrier-id interference across blocks.
- FENCE was connected to the CU stall path and drains the LSU outstanding state before the warp can continue.
- Capability and identity CSRs were added for host/runtime handshake.
- A Vitis-style SoC wrapper was added around the CU with AXI4-Lite control and AXI4-Full memory ports.
- A host-lifecycle SystemVerilog testbench was added to exercise identity check, instruction download, START/DONE, LSU memory traffic, FENCE observation, and result recovery.

## Contract Notes

The implementation follows the current `aec_g_isa_v1.json` contract:

- `FENCE` opcode uses subop 0 for CTA scope and subop 1 for DEVICE scope. The current single-LSU implementation drains all LSU outstanding work for either scope; this is conservative for the present CU.
- `BAR.SYNC` with `expected_warps=0` resolves against live warps in the same block namespace only.
- MMA hazard tracking covers D/C 8-register accumulator/result fragments and A/B 2-register FP8 fragments.
- Capability CSRs are read-only and exposed at:
  - `0x0020` magic `0xaec06001`
  - `0x0024` version `0x00010000`
  - `0x0028` geometry `0x04040820`
  - `0x002c` features `0x000007ff`
  - `0x0030` limits `0x000808ff`
  - `0x0034` memory `0x00200420`

## Remote Validation

Validated on the P2P remote Vivado/Vitis environment:

```text
source /apps/Xilinx2023/Vitis/2023.1/settings64.sh
source /opt/xilinx/xrt/setup.sh
source /opt/rh/devtoolset-9/enable
export PLATFORM=xilinx_u280_gen3x16_xdma_1_202211_1
```

Passing XSim regressions:

- `tb_scoreboard`: `SCOREBOARD TEST PASSED`
- `tb_barrier_multiblock`: `BARRIER_MULTIBLOCK TEST PASSED`
- `tb_scheduler_barrier`: `SCHEDULER_BARRIER TEST PASSED`
- `tb_cu_scoreboard_barrier`: `CU_SCOREBOARD_BARRIER TEST PASSED`
- `tb_lsu`: `LSU TEST PASSED`
- `tb_cu_multiwarp`: `CU_MULTIWARP TEST PASSED`
- `tb_soc_host_lifecycle`: `SOC_HOST_LIFECYCLE TEST PASSED`

Local checks:

- `python skills/u280-gpgpu-contest-completer/scripts/audit_submission.py .`: only missing final bitstream/xclbin artifact.
- `python tests/test_compiler.py`: passed.
- `python -m json.tool aec_g_isa_v1.json` and `python -m json.tool design.json`: passed.

## OOC Synthesis

Vivado OOC synthesis completed for both `cu_top` and `aec_soc_top` with 0 errors and 0 critical warnings.

Resource summary at `aec_soc_top` OOC:

- CLB LUTs: 88,280 / 1,303,680, 6.77%
- CLB Registers: 30,079 / 2,607,360, 1.15%
- Block RAM Tile: 100 / 2,016, 4.96%
- URAM: 0 / 960, 0.00%
- DSPs: 44 / 9,024, 0.49%

Constrained 200 MHz OOC timing is not closed:

- `cu_top`: WNS `-5.757ns`, TNS `-3777.458ns`, 796 failing endpoints.
- `aec_soc_top`: WNS `-5.757ns`, TNS `-3777.458ns`, 796 failing endpoints.
- The reported worst setup path is inside the MMA/FMA path from packed FP8 state into the FP32 FMA datapath, with 49 logic levels and a 10.739ns data path delay.

Reports archived:

- `reports/cu_top_ooc_utilization_stage10_soc_readiness.rpt`
- `reports/cu_top_ooc_timing_stage10_soc_readiness.rpt`
- `reports/soc_top_ooc_utilization_stage10_soc_readiness.rpt`
- `reports/soc_top_ooc_timing_stage10_soc_readiness.rpt`

## Remaining Gaps To Full Contest Closure

1. Timing closure is now the top RTL blocker. The MMA/FMA path needs pipelining or tile scheduling before 180-200 MHz can be honestly claimed.
2. The SoC wrapper is AXI-shaped and synthesizable, but not yet packaged as a Vitis kernel with `kernel.xml`, `connectivity.cfg`, HBM bank mapping, register slices, and platform build scripts.
3. Final evidence must be regenerated in the official contest stack, Vivado/Vitis 2022.2 and XRT 2.13.479. The current remote validation uses 2023.1 as a development environment.
4. The C++ runtime still needs real XDMA/MMIO integration, capability-manifest rejection paths, DMA cache/FENCE boundaries, and board-side error propagation.
5. Board evidence is still absent: xclbin, routed timing, power/thermal logs, long-run stability, and public model benchmark traces.
6. PyTorch/model path is not yet score-closed for ResNet/Transformer workloads. FP8 GEMM, SFU, SHFL/REDUCE, and memory kernels need model-level differential and performance validation.
7. `aec_soc_top.interrupt` is currently held low. If the Vitis/XRT integration path uses interrupts rather than polling, it must be wired to DONE/FAULT status.
