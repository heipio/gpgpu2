# Stage 8 SFU Validation

Date: 2026-07-26

## Contract

- `SFU` opcode: `0x0080`
- `SFU.RCP.f32` subop: `0`
- `SFU.EXP2.f32` subop: `1`
- Note: earlier Stage 8 drafts used split opcodes `0x0040/0x0041`; the contract audit corrected this to official `contest.md` 6.4.14.
- Supported type: FP32 (`.f32`) only
- Required precision: maximum relative error, not ULP
  - RCP: `<= 2^-10`
  - EXP2: `<= 2^-9` in normal result range
- Special values:
  - RCP: `+/-0 -> +/-Inf`, `+/-Inf -> +/-0`, NaN -> `0x7fc00000`
  - EXP2: overflow -> `+Inf`, underflow -> `+0`, NaN -> `0x7fc00000`

## Implementation

- Added `rtl/sfu.sv` with per-lane deterministic SFU approximation.
- Generated LUT files:
  - `rtl/sfu_rcp_lut.mem`
  - `rtl/sfu_exp2_lut.mem`
- LUT size: `2^12 = 4096` entries, each entry stores a 23-bit mantissa.
- Integrated SFU into `rtl/ex_stage.sv` and `rtl/wb_stage.sv`.
- Added assembler support for:
  - `RCP.f32 Rd, Ra`
  - `EXP2.f32 Rd, Ra`
- Added tests:
  - `tests/sfu_model_sweep.py`
  - `tests/sfu_test.asm`
  - `tests/run_sfu_e2e.py`

## Sweep Result

Command:

```bash
python3 tests/sfu_model_sweep.py --samples 50000
```

Result:

```text
SFU_SWEEP lut_bits=12 samples=50000
RCP  max_rel_error=1.22129917e-04 limit=9.76562500e-04 input=0x7f001000
EXP2 max_rel_error=1.69069013e-04 limit=1.95312500e-03 input=0x3c63ff67
SFU_SWEEP PASS
```

## Remote XSim Regression

Remote environment:

```bash
source /apps/Xilinx2023/Vitis/2023.1/settings64.sh
source /opt/xilinx/xrt/setup.sh
source /opt/rh/devtoolset-9/enable
export PLATFORM=xilinx_u280_gen3x16_xdma_1_202211_1
```

Passed:

- `python3 tests/run_vector_add_e2e.py`
- `python3 tests/run_alu_simt_e2e.py`
- `python3 tests/run_predicate_e2e.py`
- `python3 tests/run_sfu_e2e.py`

SFU E2E output:

```text
SFU_E2E PASS
RCP  out=['0x3f4cc7ae', '0x3e924688', '0xbe7ff800', '0x3faaa71d', '0x7f800000', '0xff800000', '0x00000000', '0x7fc00000']
EXP2 out=['0x401837f0', '0x413504f3', '0x3d800000', '0x3fd744fd', '0x3f800000', '0x3f800000', '0x7f800000', '0x7fc00000']
```

## Remote Vivado OOC

Command:

```bash
cd rtl && vivado -mode batch -source synth_cu_top_ooc.tcl
```

Result:

```text
SYNTH_CU_TOP_OOC_PASS
0 Errors
0 Critical Warnings
```

Vivado also reported:

```text
$readmem data file 'sfu_rcp_lut.mem' is read successfully
$readmem data file 'sfu_exp2_lut.mem' is read successfully
```

Utilization note: this first SFU version synthesizes the LUT tables largely into LUT/distributed-ROM resources. It is correct and synthesizable, but a later PPA pass should consider a shared or synchronous BRAM-backed SFU with valid/tag plumbing.
