# Stage 6.1 XPM IMEM Validation

Date: 2026-07-26

## Implemented

- Replaced the inferred-array IMEM implementation in `rtl/imem.sv` with an explicit `xpm_memory_sdpram`.
- Kept the Stage 6 module interface unchanged, so `cu_top.sv` and `csr_regfile.sv` do not need port-level changes.
- Configured the XPM as a simple dual-port RAM:
  - `MEMORY_SIZE = 131072` bits.
  - `WRITE_DATA_WIDTH_A = 32`.
  - `BYTE_WRITE_WIDTH_A = 32`.
  - `READ_DATA_WIDTH_B = 128`.
  - `READ_LATENCY_B = 1`.
  - `CLOCKING_MODE = "common_clock"`.
  - `MEMORY_PRIMITIVE = "block"`.
- Address mapping:
  - Host Port A writes 32-bit words using `addra = {2'b00, axil_word_addr_i}`.
  - GPU Port B reads 128-bit instructions using `addrb = if_addr_i`.
  - Little-endian instruction loading remains: word 0 -> `[31:0]`, word 3 -> `[127:96]`.
- Updated `tb_loop_system.sv` and `tb_divergent_brx_system.sv` to stop using the removed `u_imem.mem` backdoor and instead load instructions through AXI-Lite.

## Remote XSim Regression

Tool: Vivado/XSim 2023.1, with XPM simulation library enabled via `-L xpm`.

Results:

```text
tb_system               : [SYSTEM TEST] PASS
tb_loop_system          : [LOOP TEST] PASS
tb_divergent_brx_system : [DIVERGENT BRX TEST] PASS
```

## Remote OOC Synthesis

Tool: Vivado 2023.1 on U280 part `xcu280-fsvh2892-2L-e`.

Result:

```text
synth_design completed successfully
Synthesis finished with 0 errors, 0 critical warnings
```

IMEM resource result:

```text
u_imem_xpm / xpm_memory_base : RAMB36E2 = 4
u_imem LUT/LUTRAM            : 0
```

Top-level RAMB36 increased from 24 to 28, matching the expected 16 KiB IMEM cost.

Representative synthesis line:

```text
4 K x 32 write port, 1 K x 128 read port, Port A and B, RAMB36E2 = 4
```

## Contest-Contract Notes

- This change removes the previous LUTRAM-heavy IMEM implementation and makes instruction memory scalable enough for RTL hardening.
- The tested Host-driven path still avoids IMEM/VRF backdoor loading in `tb_system.sv`.
- The existing `IMEM_WINDOW = 0x1000..0x1fff` exposes 4096 bytes, enough for 256 128-bit instructions. The XPM stores 1024 128-bit instructions. To expose the full depth through Host loading, the CSR window should be expanded in a later ABI-compatible revision.
- XPM initialization is disabled (`MEMORY_INIT_FILE="none"`, `USE_MEM_INIT=0`) because the Stage 6 contract loads code through AXI-Lite. XPM simulation only accepts `.mem` init files, while the older `inst.hex` path is no longer the primary boot path.

## Compatibility Note

This validation used the available remote Vivado 2023.1 installation. Final contest evidence still needs Vivado/Vitis 2022.2 compatibility validation.
