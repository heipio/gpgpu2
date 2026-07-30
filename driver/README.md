# AEC-G XRT Host Driver Skeleton

This directory contains the first XRT C++ host entry point for the U280 Vitis integration stage.

## ABI

- Kernel name: `aec_gpgpu`
- Compute unit name: `aec_gpgpu_1`
- Control interface: AXI4-Lite `s_axi_control`
- Global memory interface: four AXI4 masters `m_axi_gmem0..3`, 512-bit data each
- IMEM programming window: `0x1000..0x1fff`, written as 32-bit little-endian words
- Launch protocol: write `CSR_PC`, write `CSR_CTRL.START`, poll `CSR_STATUS.DONE` or `CSR_STATUS.FAULT`

The SoC top exposes four HBM AXI masters. Kernel-visible 32-bit addresses use `addr[31:30]` as the HBM port selector and `addr[29:0]` as the offset inside that port. Do not truncate arbitrary 64-bit XRT physical BO addresses into kernel operands.

## Build On U280 Host

```bash
source /apps/Xilinx2023/Vitis/2023.1/settings64.sh
source /opt/xilinx/xrt/setup.sh
source /opt/rh/devtoolset-9/enable
make -C platform host
```
