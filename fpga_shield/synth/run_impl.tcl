# run_impl.tcl
set project_name "total_shield_arty"
set project_dir "./vivado_project"
set part "xc7a100tcsg324-1"

create_project -force $project_name $project_dir -part $part
set_property target_language Verilog [current_project]

set rtl_files [glob -nocomplain ../rtl/*.v]
if {[llength $rtl_files] == 0} { error "No Verilog files found" }
add_files -norecurse $rtl_files
set_property include_dirs [list ../rtl] [current_fileset]

set constr_file "../constraints/arty_a7.xdc"
if {[file exists $constr_file]} {
    add_files -fileset constrs_1 -norecurse $constr_file
}

set_property top sentinel_ip_core_top [current_fileset]
launch_runs synth_1 -jobs 2
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1
exit
