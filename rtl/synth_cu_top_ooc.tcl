set script_dir [file dirname [file normalize [info script]]]
cd $script_dir

create_project -in_memory aec_cu_ooc -part xcu280-fsvh2892-2L-e
set_property target_language Verilog [current_project]
set_property XPM_LIBRARIES {XPM_MEMORY} [current_project]
set_property verilog_define {AEC_USE_XILINX_FP_IP} [current_fileset]

read_ip ip/fp32_fma/aec_fp32_fma/aec_fp32_fma.xci
generate_target synthesis [get_ips aec_fp32_fma]
synth_ip -force [get_ips aec_fp32_fma]

read_verilog -sv {
  aec_pkg.sv
  alu_lane.sv
  sfu.sv
  sfu_core.sv
  csr_regfile.sv
  fetch_decode.sv
  id_stage.sv
  issue_stage.sv
  vrf_lane.sv
  vrf_top.sv
  prf_top.sv
  fp32_fma_ip_wrap.sv
  fpu_core.sv
  warp_collective_core.sv
  warp_scheduler.sv
  scoreboard.sv
  barrier_unit.sv
  mma_core.sv
  simt_stack.sv
  ex_stage.sv
  lsu.sv
  wb_stage.sv
  trace_logger.sv
  imem.sv
  if_stage.sv
  cu_top.sv
  aec_axi_hbm_4way_router.sv
  aec_soc_top.sv
}

synth_design -top cu_top -part xcu280-fsvh2892-2L-e -mode out_of_context
create_clock -name clk_i -period 5.000 [get_ports clk_i]
set sfu_src_regs [get_cells -hier -regexp -quiet {.*u_sfu_core/src_q_reg.*}]
set sfu_result_regs [get_cells -hier -regexp -quiet {.*u_sfu_core/result_q_reg.*}]
puts "SFU_MULTICYCLE_SRC_REGS=[llength $sfu_src_regs] RESULT_REGS=[llength $sfu_result_regs]"
if {[llength $sfu_src_regs] > 0 && [llength $sfu_result_regs] > 0} {
  set_multicycle_path -setup 8 -from $sfu_src_regs -to $sfu_result_regs
  set_multicycle_path -hold 7 -from $sfu_src_regs -to $sfu_result_regs
}
report_utilization -file cu_top_ooc_utilization.rpt
report_timing_summary -file cu_top_ooc_timing_summary.rpt
puts "SYNTH_CU_TOP_OOC_PASS"
