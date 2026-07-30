#!/usr/bin/env bash
set -euo pipefail

source /apps/Xilinx2023/Vitis/2023.1/settings64.sh
source /opt/xilinx/xrt/setup.sh
source /opt/rh/devtoolset-9/enable

export PLATFORM="${PLATFORM:-xilinx_u280_gen3x16_xdma_1_202211_1}"
make -C "$(dirname "$0")" "$@"
