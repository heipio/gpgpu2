# Vitis RTL-kernel packaging helper for AEC-G.
#
# Usage:
#   vivado -mode batch -source platform/package_kernel.tcl -tclargs --check-only
#   vivado -mode batch -source platform/package_kernel.tcl -tclargs --ipxact
#   vivado -mode batch -source platform/package_kernel.tcl -tclargs ../bitstream/aec_gpgpu.hw.xo
#
# The check-only mode is intentionally fast for CI/toolchain validation.
# The --ipxact mode generates a Vivado IP-XACT component under platform/ip_repo.

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file dirname $script_dir]
set rtl_dir [file join $repo_dir rtl]
set kernel_xml [file join $script_dir kernel.xml]

set rtl_sources {
  aec_pkg.sv
  aec_soc_top.v
  aec_soc_core.sv
  aec_axi_hbm_4way_router.sv
  cu_top.sv
  alu_lane.sv
  barrier_unit.sv
  csr_regfile.sv
  ex_stage.sv
  fetch_decode.sv
  fp32_fma_ip_wrap.sv
  fpu_core.sv
  id_stage.sv
  if_stage.sv
  imem.sv
  issue_stage.sv
  lsu.sv
  mma_core.sv
  prf_top.sv
  scoreboard.sv
  sfu.sv
  sfu_core.sv
  simt_stack.sv
  vrf_lane.sv
  vrf_top.sv
  warp_collective_core.sv
  warp_scheduler.sv
  wb_stage.sv
}

proc require_file {path} {
  if {![file exists $path]} {
    error "missing required file: $path"
  }
}

proc set_or_add_bus_parameter {bus_if param_name param_value} {
  set param_obj [ipx::get_bus_parameters $param_name -of_objects $bus_if -quiet]
  if {[llength $param_obj] == 0} {
    set param_obj [ipx::add_bus_parameter $param_name $bus_if]
  }
  set_property value $param_value $param_obj
}

foreach src $rtl_sources {
  require_file [file join $rtl_dir $src]
}
require_file $kernel_xml

if {[llength $argv] > 0 && [lindex $argv 0] eq "--check-only"} {
  puts "AEC Vitis package check passed"
  puts "RTL source count: [llength $rtl_sources]"
  puts "Kernel XML: $kernel_xml"
  exit 0
}

set ip_dir [file normalize [file join $script_dir ip_repo aec_gpgpu_1_0]]
set package_ipxact_only 0
if {[llength $argv] > 0 && [lindex $argv 0] eq "--ipxact"} {
  set package_ipxact_only 1
}

if {[llength $argv] < 1} {
  error "expected output .xo path or --check-only"
}

set xo_path [file normalize [lindex $argv 0]]
set work_dir [file normalize [file join $repo_dir _x aec_gpgpu_pack]]
file mkdir $work_dir
create_project -force aec_gpgpu_pack $work_dir -part xcu280-fsvh2892-2L-e
set_property target_language Verilog [current_project]
set_property XPM_LIBRARIES {XPM_MEMORY} [current_project]
set_property verilog_define {AEC_USE_XILINX_FP_IP} [current_fileset]

foreach src $rtl_sources {
  if {[file extension $src] eq ".v"} {
    read_verilog [file join $rtl_dir $src]
  } else {
    read_verilog -sv [file join $rtl_dir $src]
  }
}

set xci_path [file join $rtl_dir ip fp32_fma aec_fp32_fma aec_fp32_fma.xci]
if {[file exists $xci_path]} {
  import_ip -files $xci_path
  generate_target synthesis [get_ips aec_fp32_fma]
}
foreach mem_file {sfu_rcp_lut.mem sfu_exp2_lut.mem} {
  set mem_path [file join $rtl_dir $mem_file]
  if {[file exists $mem_path]} {
    add_files -norecurse $mem_path
  }
}

set_property top aec_soc_top [current_fileset]
update_compile_order -fileset sources_1

file delete -force $ip_dir
file mkdir $ip_dir
ipx::package_project -root_dir $ip_dir -vendor user.org -library user -taxonomy /UserIP -import_files -force
set core [ipx::current_core]
set_property name aec_gpgpu $core
set_property display_name {AEC-G U280 GPGPU RTL Kernel} $core
set_property description {AEC-G SIMT GPGPU RTL kernel wrapper with AXI4-Lite control and four AXI4 HBM master ports} $core
set_property version 1.0 $core
set clk_intf [ipx::get_bus_interfaces ap_clk -of_objects $core]
if {[llength $clk_intf] > 0} {
  set_or_add_bus_parameter $clk_intf FREQ_HZ 200000000
  set_or_add_bus_parameter $clk_intf ASSOCIATED_BUSIF {s_axi_control:m_axi_gmem0:m_axi_gmem1:m_axi_gmem2:m_axi_gmem3}
}
foreach bus_name {s_axi_control m_axi_gmem0 m_axi_gmem1 m_axi_gmem2 m_axi_gmem3} {
  set bus_if [ipx::get_bus_interfaces $bus_name -of_objects $core -quiet]
  if {[llength $bus_if] > 0} {
    set_or_add_bus_parameter $bus_if ASSOCIATED_CLOCK ap_clk
    set_or_add_bus_parameter $bus_if FREQ_HZ 200000000
  }
}
ipx::update_checksums $core
ipx::save_core $core

puts "AEC RTL sources and kernel metadata are valid for Vitis packaging."
puts "IP-XACT component: [file join $ip_dir component.xml]"
if {$package_ipxact_only} {
  close_project
  exit 0
}
puts "XO output requested: $xo_path"
file mkdir [file dirname $xo_path]
package_xo -force -xo_path $xo_path -kernel_name aec_gpgpu -kernel_xml $kernel_xml -ip_directory $ip_dir -ctrl_protocol user_managed
puts "XO output: $xo_path"
close_project
