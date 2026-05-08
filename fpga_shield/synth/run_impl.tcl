# run_impl.tcl
# Full flow: synthesis → implementation → bitstream generation

set project_name "total_shield_arty"
set project_dir "./vivado_project"
set part "xc7a100tcsg324-1"

create_project -force $project_name $project_dir -part $part
set_property target_language Verilog [current_project]

# Add RTL files
set rtl_files [glob -nocomplain ../rtl/*.v]
if {[llength $rtl_files] == 0} { error "No Verilog files found" }
add_files -norecurse $rtl_files
set_property include_dirs [list ../rtl] [current_fileset]

# Add constraints
set constr_file "../constraints/arty_a7.xdc"
if {[file exists $constr_file]} {
    add_files -fileset constrs_1 -norecurse $constr_file
} else {
    puts "Warning: No constraints file. Timing may be incomplete."
}

set_property top sentinel_ip_core_top [current_fileset]

# Synthesis
puts "Running synthesis..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1
open_run synth_1

# Implementation
puts "Running implementation..."
launch_runs impl_1 -jobs 4
wait_on_run impl_1
open_run impl_1

# Reports
file mkdir ./impl_reports
report_utilization -file ./impl_reports/impl_util.rpt
report_timing_summary -file ./impl_reports/impl_timing.rpt
report_power -file ./impl_reports/impl_power.rpt

# Generate bitstream
puts "Generating bitstream..."
launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1

# Copy bitstream to output folder
set bitstream_file [get_property BITSTREAM_FILE [get_runs impl_1]]
file mkdir ./bitstream
file copy -force $bitstream_file ./bitstream/total_shield_arty.bit
puts "Bitstream generated: ./bitstream/total_shield_arty.bit"

puts "Flow completed."
