# Multi-AXI / IP-XACT / XO Vitis Integration Validation

## Implemented

- Split the Vitis-visible top into a Verilog-2001 wrapper and SystemVerilog core:
  - `rtl/aec_soc_top.v`
  - `rtl/aec_soc_core.sv`
  - This closes the previous IP packager SystemVerilog-top warning while preserving synthesizable SV internals.
- Expanded the SoC top from one Vitis-visible memory master to four AXI4 masters:
  - `m_axi_gmem0`
  - `m_axi_gmem1`
  - `m_axi_gmem2`
  - `m_axi_gmem3`
- Added `rtl/aec_axi_hbm_4way_router.sv`.
  - Uses AEC-G 32-bit device address bits `addr[31:30]` as the HBM port selector.
  - Uses `addr[29:0]` as the offset inside the selected HBM pseudo-channel window.
  - Keeps the existing CU/LSU request stream in-order and protocol-compatible.
- Updated `platform/kernel.xml` with four Vitis memory ports and four pointer args.
- Updated `platform/connectivity.cfg`:
  - `m_axi_gmem0 -> HBM[0]`
  - `m_axi_gmem1 -> HBM[1]`
  - `m_axi_gmem2 -> HBM[2]`
  - `m_axi_gmem3 -> HBM[3]`
- Updated `driver/aec_xrt_host.cpp` to allocate four XRT BOs using `kernel.group_id(0..3)`.
- Updated `platform/package_kernel.tcl` to generate a self-contained Vivado IP-XACT component under `platform/ip_repo/aec_gpgpu_1_0/component.xml`.
- Added explicit clock/interface metadata for `ap_clk`, `s_axi_control`, and `m_axi_gmem0..3`, including `FREQ_HZ=200000000` and clock association.
- Generated a formal Vitis RTL kernel object:
  - `bitstream/aec_gpgpu.hw.xo`
  - Size after contract-audit rebuild: `90305` bytes

## Remote Validation

Validated on `contest5@127.0.0.1:2222` with:

```bash
source /apps/Xilinx2023/Vitis/2023.1/settings64.sh
source /opt/xilinx/xrt/setup.sh
source /opt/rh/devtoolset-9/enable
export PLATFORM=xilinx_u280_gen3x16_xdma_1_202211_1
```

Passed:

- `make -C platform check-kernel`
  - Vivado 2023.1 launched.
  - All 28 packaged RTL source files were present.
  - `platform/kernel.xml` was present and XML-valid.
- `make -C platform ipxact`
  - Generated `platform/ip_repo/aec_gpgpu_1_0/component.xml`.
  - Vivado inferred AXI interfaces `m_axi_gmem0..3` and `s_axi_control`.
  - IP repo is self-contained under `platform/ip_repo/aec_gpgpu_1_0/src`.
  - Closed previous packager warning IDs:
    - `IP_Flow 19-5101` SystemVerilog top packaging warning: no longer present.
    - `IP_Flow 19-3158` AXI `FREQ_HZ` warning: no longer present.
    - `IP_Flow 19-5661` AXI clock association warning: no longer present.
    - `IP_Flow 19-11770` AXI frequency propagation warning: no longer present.
  - Remaining note is info-level only: `IP_Flow 19-5654`, indicating a Verilog wrapper with SystemVerilog child sources. It is not emitted as `WARNING` or `CRITICAL WARNING`.
- `make -C platform xo`
  - Passed with return code `0`.
  - Generated `bitstream/aec_gpgpu.hw.xo`.
  - Log scan found no `ERROR:`, no `CRITICAL WARNING`, and none of the previous IP packager warning IDs listed above.
- `make -C platform host`
  - XRT C++14 host compiled against `/opt/xilinx/xrt`.
- `make -C platform emconfig`
  - U280 platform resolved and `emconfig.json` generated.
- `vivado -mode batch -source rtl/synth_soc_top_ooc.tcl`
  - Synthesis completed with 0 errors and 0 critical warnings.
  - Timing at 5.000 ns: WNS `+0.339 ns`, TNS `0.000 ns`.
  - Utilization snapshot: CLB LUTs `87839`, CLB registers `39177`, RAMB36/FIFO `100`, DSP `44`.
- Contract audit rebuild after branch target-field correction:
  - `make -C platform check-kernel`: passed.
  - `make -C platform ipxact`: passed.
  - `make -C platform xo`: passed; regenerated `bitstream/aec_gpgpu.hw.xo`.
  - `vivado -mode batch -source rtl/synth_soc_top_ooc.tcl`: passed with WNS `+0.339 ns`.
  - XO archive contains `kernel.xml`, `component.xml`, `aec_soc_top.v`, and `aec_soc_core.sv`; it no longer contains stale `aec_soc_top.sv`.

## Contract Notes

- This satisfies the contest requirement to avoid ambiguous HBM placement and exposes at least four independent HBM pseudo-channel bindings to Vitis/XRT.
- This is not yet full-bandwidth scatter/gather concurrency: the current CU has one in-order LSU request stream, routed to one of four ports per request. Full HBM throughput still requires multi-issue LSU queues, multiple CUs, or independent memory requesters.
- Kernel-visible addresses remain 32-bit AEC-G addresses. Runtime/host code must translate 64-bit XRT/device pointers into these address windows; direct truncation remains illegal.
- Full `v++ -l -t hw` xclbin link was not run in this pass because it is a long build. The prerequisite RTL kernel `.xo` now exists.

## Remaining To Full Contest Closure

- Run `v++ -l -t hw` for `xilinx_u280_gen3x16_xdma_1_202211_1` and inspect link/timing summaries.
- Execute the XRT host against the real `.xclbin` on U280 and collect board correctness logs.
- Upgrade memory subsystem from routed single-stream LSU to genuinely concurrent HBM traffic.
- Run official model workloads, accuracy gates, performance/energy measurement, 30-minute stability, and final submission audit.
