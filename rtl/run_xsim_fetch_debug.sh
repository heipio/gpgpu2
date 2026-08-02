#!/usr/bin/env bash
set -euo pipefail

rtl_dir="$(cd "$(dirname "$0")" && pwd)"
run_dir="${rtl_dir}/fetch_tag_debug"
rm -rf "${run_dir}"
mkdir -p "${run_dir}"
cd "${run_dir}"
cp "${rtl_dir}/sfu_rcp_lut.mem" "${rtl_dir}/sfu_exp2_lut.mem" .

sources=(
  aec_pkg.sv cu_top.sv alu_lane.sv barrier_unit.sv csr_regfile.sv ex_stage.sv
  fetch_decode.sv fp32_fma_ip_wrap.sv fpu_core.sv id_stage.sv if_stage.sv
  imem.sv issue_stage.sv lsu.sv mma_core.sv prf_top.sv scoreboard.sv sfu.sv
  sfu_core.sv simt_stack.sv vrf_lane.sv vrf_top.sv warp_collective_core.sv
  warp_scheduler.sv wb_stage.sv trace_logger.sv
)
for source in "${sources[@]}"; do
  xvlog -sv "${rtl_dir}/${source}"
done
xvlog -sv "${rtl_dir}/tb_cu_multiwarp.sv"
xelab -debug all -L xpm tb_cu_multiwarp -s tb_fetch_tag_snapshot
xsim tb_fetch_tag_snapshot -wdb fetch_tag.wdb -tclbatch "${rtl_dir}/xsim_fetch_tag.tcl"
