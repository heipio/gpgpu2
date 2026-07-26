set script_dir [file dirname [file normalize [info script]]]
cd $script_dir

create_project -in_memory aec_cu_ooc -part xcu280-fsvh2892-2L-e
set_property target_language Verilog [current_project]
set_property XPM_LIBRARIES {XPM_MEMORY} [current_project]

read_verilog -sv {
  aec_pkg.sv
  alu_lane.sv
  sfu.sv
  csr_regfile.sv
  fetch_decode.sv
  id_stage.sv
  issue_stage.sv
  vrf_lane.sv
  vrf_top.sv
  prf_top.sv
  simt_stack.sv
  ex_stage.sv
  lsu.sv
  wb_stage.sv
  trace_logger.sv
  imem.sv
  if_stage.sv
  cu_top.sv
}

synth_design -top cu_top -part xcu280-fsvh2892-2L-e -mode out_of_context
report_utilization -file cu_top_ooc_utilization.rpt
report_timing_summary -file cu_top_ooc_timing_summary.rpt
puts "SYNTH_CU_TOP_OOC_PASS"
