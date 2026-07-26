set script_dir [file dirname [file normalize [info script]]]
set rtl_dir [file normalize [file join $script_dir ..]]
set ip_dir [file normalize [file join $rtl_dir ip fp32_fma]]

file mkdir $ip_dir
create_project -in_memory aec_fp32_fma_ip -part xcu280-fsvh2892-2L-e
set_property target_language Verilog [current_project]

create_ip -name floating_point -vendor xilinx.com -library ip -module_name aec_fp32_fma -dir $ip_dir

set ip [get_ips aec_fp32_fma]
set_property -dict [list \
  CONFIG.Operation_Type {FMA} \
  CONFIG.A_Precision_Type {Single} \
  CONFIG.Result_Precision_Type {Single} \
  CONFIG.Flow_Control {NonBlocking} \
  CONFIG.Maximum_Latency {false} \
  CONFIG.C_Latency {1} \
  CONFIG.Has_ACLKEN {true} \
  CONFIG.Has_ARESETn {true} \
] $ip

generate_target {instantiation_template simulation synthesis} $ip
export_ip_user_files -of_objects $ip -no_script -sync -force -quiet
puts "AEC_FP32_FMA_IP_CREATED [get_property IP_FILE $ip]"
