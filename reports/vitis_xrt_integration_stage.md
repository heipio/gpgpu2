# Vitis / XRT Integration Stage

## Implemented

- Added Vitis RTL-kernel metadata in `platform/kernel.xml` for `aec_gpgpu`.
- Added U280 HBM mapping in `platform/connectivity.cfg`: `aec_gpgpu_1.m_axi_gmem0..3 -> HBM[0]..HBM[3]`.
- Added `platform/Makefile` and `platform/build_hw.sh` with `env-check`, `check-kernel`, `host`, `xo`, `xclbin`, and `emconfig` targets.
- Added `driver/aec_xrt_host.cpp`, an XRT C++14 host skeleton that:
  - loads an xclbin,
  - opens `aec_gpgpu:{aec_gpgpu_1}`,
  - checks AEC capability CSR magic/version/geometry/features,
  - writes `.aecbin` words through the AXI-Lite IMEM window,
  - starts the kernel and polls DONE/FAULT status.
- Added `platform/aec_gpgpu_kernel.json` to keep the kernel, CSR, HBM, and toolchain contract machine-readable.

## U280 Contract Notes

- Validation environment follows `E:/gpgpu/U280.md`: Vitis/Vivado 2023.1 with XRT/platform 2022.1.
- The contest contract still requires final reproducible evidence on the official accepted flow. The project records this risk in `design.json`.
- Current SoC top has four 512-bit AXI masters. The CU/LSU request stream is still in-order and routed by `addr[31:30]`; full U280 bandwidth requires concurrent request generation.
- `aec_soc_top.interrupt` remains a reserved polling-only path. Host completion currently uses CSR polling.

## Verification

Remote validation was run on `contest5@127.0.0.1:2222` using the U280 environment from `E:/gpgpu/U280.md`:

```bash
source /apps/Xilinx2023/Vitis/2023.1/settings64.sh
source /opt/xilinx/xrt/setup.sh
source /opt/rh/devtoolset-9/enable
export PLATFORM=xilinx_u280_gen3x16_xdma_1_202211_1
```

Passed checks:

- `make -C platform env-check`
  - `v++ v2023.1`
  - `/opt/xilinx/platforms/xilinx_u280_gen3x16_xdma_1_202211_1` found
- `make -C platform check-kernel`
  - Vivado 2023.1 launched successfully
  - `package_kernel.tcl --check-only` found all 28 required RTL source files
  - `platform/kernel.xml` found
- `make -C platform host`
  - `driver/aec_xrt_host.cpp` compiled successfully against `/opt/xilinx/xrt/include` and `/opt/xilinx/xrt/lib`
- `make -C platform emconfig`
  - `emconfigutil` resolved the U280 platform and generated `bitstream/emconfig.json`
- `make -C platform ipxact`
  - Vivado generated `platform/ip_repo/aec_gpgpu_1_0/component.xml`
  - AXI interfaces `m_axi_gmem0..3` and `s_axi_control` were inferred
- `vivado -mode batch -source rtl/synth_soc_top_ooc.tcl`
  - SoC OOC synthesis passed with 0 errors / 0 critical warnings
  - 5 ns timing summary: WNS `+0.339 ns`, TNS `0.000 ns`

Not run in this pass:

- Full `make -C platform xclbin` / `v++ -l -t hw` hardware link. This is expected to be a long build and should be run in a dedicated build window once RTL-kernel IP-XACT bus-interface binding is finalized.

## Remaining To Full Contest Closure

- Final `.xo` emission from the IP-XACT component and `v++ -l -t hw` xclbin link for U280.
- Board execution with the generated xclbin and real XRT memory movement.
- True concurrent HBM traffic beyond the current in-order LSU stream routed over four top-level ports.
- Final scoring workloads, logs, correctness traces, timing/utilization reports, and submission bundle.
