# Stage 9 MMA Base Validation

Date: 2026-07-26

## Contract Alignment

- Official source: `contest.md` section 6.4.13.
- `MMA.m16n16k16.e4m3.f32` opcode is `0x0070`.
- `Pred/Ctrl.type` is `0xb` for E4M3FN input with FP32 accumulation.
- `Pred/Ctrl.ctrl` subop is `0x0` for `m16n16k16`.
- `dst`, `src1`, `src2_or_imm32[15:0]`, and `src3_or_immext[15:0]` encode D/A/B/C base GPRs.
- A/B base registers must be even aligned and `<= R254`.
- C/D base registers must be 8-register aligned and `<= R248`.
- Per-lane fragment layout follows official 6.4.13:
  - `row = lane >> 1`
  - `half = lane & 1`
  - `col_base = 8 * half`
  - `k_base = 8 * half`
  - `b_col = lane >> 1`

## Implemented Files

- `aec_g_isa_v1.json`
- `compiler/aec_assembler.py`
- `compiler/compiler.py`
- `tests/mma_model.py`
- `tests/mma_vectors.json`
- `rtl/fp8_decoder.sv`
- `rtl/fp32_fma_ip_wrap.sv`
- `rtl/ip/create_fp32_fma_ip.tcl`
- `rtl/tb_fp8_decoder.sv`
- `rtl/tb_fp32_fma_ip_wrap.sv`

## Local Checks

- `python -m json.tool aec_g_isa_v1.json`
- `python tests/mma_model.py -o tests/mma_vectors.json`
- `python tests/test_assembler.py`
- `python tests/test_compiler.py`

## Remote Vivado/XSim Checks

Remote directory: `/home/contest5/gpgpu_stage9_base`

Environment:

```sh
source /apps/Xilinx2023/Vitis/2023.1/settings64.sh
source /opt/xilinx/xrt/setup.sh
source /opt/rh/devtoolset-9/enable
export PLATFORM=xilinx_u280_gen3x16_xdma_1_202211_1
```

Validated:

- `rtl/tb_fp8_decoder.sv`: `FP8_DECODER TEST PASSED`
- `rtl/ip/create_fp32_fma_ip.tcl`: generated `rtl/ip/fp32_fma/aec_fp32_fma/aec_fp32_fma.xci`
- `rtl/tb_fp32_fma_ip_wrap.sv`: `FP32_FMA_IP_WRAP TEST PASSED`

## Remaining Stage 9 Work

- Implement `mma_core.sv` around FP8 decode and FP32 FMA sequencing.
- Integrate MMA multi-cycle issue/stall/writeback into `ex_stage.sv` and `cu_top.sv`.
- Add end-to-end `mma_test.asm` and `run_mma_e2e.py`.
- Run XSim against the generated MMA vectors and then synthesize the integrated datapath.
