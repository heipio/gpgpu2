create_project -in_memory fp_probe -part xcu280-fsvh2892-2L-e
create_ip -name floating_point -vendor xilinx.com -library ip -module_name fp_probe

foreach p [lsort [list_property [get_ips fp_probe]]] {
  if {[string match CONFIG.* $p]} {
    puts "$p = [get_property $p [get_ips fp_probe]]"
  }
}
