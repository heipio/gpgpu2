# The SFU request registers are written only in SFU_IDLE.  They remain stable
# throughout SFU_WAIT, while result_q is written exactly COMPUTE_LATENCY cycles
# later.  These paths are therefore intentional 8-cycle datapaths, not
# single-cycle paths.  The matching hold exception preserves the real launch /
# capture relationship and is valid only for the fixed-latency sfu_core.
set sfu_src_regs [get_cells -hier -quiet -filter {IS_SEQUENTIAL && NAME =~ *u_sfu_core/src_q_reg*}]
set sfu_subop_regs [get_cells -hier -quiet -filter {IS_SEQUENTIAL && NAME =~ *u_sfu_core/subop_q_reg*}]
set sfu_result_regs [get_cells -hier -quiet -filter {IS_SEQUENTIAL && NAME =~ *u_sfu_core/result_q_reg*}]

set_multicycle_path 8 -setup -from $sfu_src_regs -to $sfu_result_regs
set_multicycle_path 7 -hold  -from $sfu_src_regs -to $sfu_result_regs
set_multicycle_path 8 -setup -from $sfu_subop_regs -to $sfu_result_regs
set_multicycle_path 7 -hold  -from $sfu_subop_regs -to $sfu_result_regs
