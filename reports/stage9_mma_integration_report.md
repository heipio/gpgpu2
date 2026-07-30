# Stage 9 MMA Integration Report

Date: 2026-07-28

## Contract Points Implemented

- `MMA.m16n16k16.e4m3.f32` uses opcode `0x0070`, type `0xb`, subop `0`.
- D/C fragment bases must be 8-register aligned and <= R248.
- A/B fragment bases must be even aligned and <= R254.
- Partial active-mask or predicated MMA is rejected with `AEC_FAULT_ILLEGAL_INSTRUCTION`.
- Fragment layout follows contest.md section 6.4.13:
  - lane `l`: `row=l>>1`, `half=l&1`, `col_base=8*half`, `k_base=8*half`, `b_col=l>>1`
  - A/B FP8 bytes are read from two packed 32-bit registers per logical lane.
  - C/D FP32 fragments span 8 registers.
- Accumulation is serialized in strict `k=0..15` order through the FP32 FMA wrapper.

## RTL Files Changed

- `rtl/mma_core.sv`: multi-cycle MMA engine with VRF fragment gather, serial FP32 FMA accumulation, and multi-register writeback.
- `rtl/vrf_top.sv`: added MMA read override and MMA writeback arbitration ports.
- `rtl/cu_top.sv`: connected MMA dispatch, pipeline stall, VRF arbitration, fault propagation, and trace writeback mux.
- `rtl/fp32_fma_ip_wrap.sv`: existing wrapper used by MMA; behavioral path is for simulation, Xilinx Floating-Point IP path is selected with `AEC_USE_XILINX_FP_IP`.
- `rtl/ip/fp32_fma/aec_fp32_fma/aec_fp32_fma.xci`: Xilinx Floating-Point FMA IP consumed by the OOC synthesis script.
- `rtl/tb_mma_core.sv`: standalone XSim test for all-one FP8 fragments producing FP32 `16.0` in every D fragment.
- `rtl/synth_cu_top_ooc.tcl`: includes `fp32_fma_ip_wrap.sv` and `mma_core.sv` in CU OOC synthesis.

## Remote Validation

Remote environment:

```text
host: contest5@127.0.0.1:2222
repo: /home/contest5/gpgpu_stage9_base
Vivado/Vitis: 2023.1
XRT: /opt/xilinx/xrt
```

Commands run:

```bash
xvlog -sv aec_pkg.sv fp32_fma_ip_wrap.sv mma_core.sv tb_mma_core.sv
xelab tb_mma_core -s tb_mma_core_sim
xsim tb_mma_core_sim -runall
```

Result:

```text
MMA_CORE TEST PASSED
```

Full CU SystemVerilog analysis also passed:

```bash
xvlog -sv aec_pkg.sv alu_lane.sv sfu.sv csr_regfile.sv fetch_decode.sv id_stage.sv issue_stage.sv vrf_lane.sv vrf_top.sv prf_top.sv fp32_fma_ip_wrap.sv mma_core.sv simt_stack.sv ex_stage.sv lsu.sv wb_stage.sv trace_logger.sv imem.sv if_stage.sv cu_top.sv
```

OOC synthesis with real Xilinx Floating-Point FMA IP:

```text
SYNTH_CU_TOP_OOC_PASS
0 Errors, 0 Critical Warnings
Vivado read design checkpoint aec_fp32_fma.dcp for u_mma_core/u_fp32_fma/u_aec_fp32_fma
```

Key utilization from `cu_top_ooc_utilization.rpt`:

```text
CLB LUTs        58107
CLB Registers   23542
RAMB36E2            28
DSPs                26
URAM                 0
```

## Remaining Risk

The current MMA core is correctness-first and serializes one FMA engine across all 32 logical lanes, 8 output elements, and 16 K steps. This is contract-aligned but slow. Final performance work should replicate or tile the FMA datapath after end-to-end model correctness is stable.

OOC timing still reports missing top-level clock-buffer context for `clk_i`; use full platform constraints for final timing closure.
