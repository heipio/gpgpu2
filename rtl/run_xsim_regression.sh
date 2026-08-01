#!/usr/bin/env bash
# Reproducible XSim regression runner for the synthesizable AEC-G RTL.
set -euo pipefail

rtl_dir="$(cd "$(dirname "$0")" && pwd)"
run_dir="${rtl_dir}/xsim_regression"
rm -rf "${run_dir}"
mkdir -p "${run_dir}"
cd "${run_dir}"

# $readmemh resolves filenames relative to XSim's launch directory.
cp "${rtl_dir}/sfu_rcp_lut.mem" "${rtl_dir}/sfu_exp2_lut.mem" .

sources=(
  aec_pkg.sv aec_soc_top.v aec_soc_core.sv aec_axi_hbm_4way_router.sv
  cu_top.sv alu_lane.sv barrier_unit.sv csr_regfile.sv ex_stage.sv
  fetch_decode.sv fp32_fma_ip_wrap.sv fpu_core.sv id_stage.sv if_stage.sv
  imem.sv issue_stage.sv lsu.sv mma_core.sv prf_top.sv scoreboard.sv
  sfu.sv sfu_core.sv simt_stack.sv vrf_lane.sv vrf_top.sv
  warp_collective_core.sv warp_scheduler.sv wb_stage.sv trace_logger.sv
)
tests=(
  tb_soc_host_lifecycle tb_cu_multiwarp tb_cu_scoreboard_barrier
  tb_mma_core tb_sfu_core tb_fpu_collective
)

for source in "${sources[@]}"; do
  xvlog -sv "${rtl_dir}/${source}"
done
for test in "${tests[@]}"; do
  xvlog -sv "${rtl_dir}/${test}.sv"
  xelab -L xpm "${test}" -s "${test}_snapshot"
  xsim "${test}_snapshot" -runall > "${test}.log" 2>&1
  if grep -Eq 'Fatal:|ERROR:|CRITICAL WARNING:' "${test}.log"; then
    cat "${test}.log"
    exit 1
  fi
  if ! grep -Eq 'TEST PASSED|\[SYSTEM TEST\] PASS|SOC_HOST_LIFECYCLE TEST PASSED' "${test}.log"; then
    cat "${test}.log"
    exit 1
  fi
done

echo "XSim RTL regression passed"
