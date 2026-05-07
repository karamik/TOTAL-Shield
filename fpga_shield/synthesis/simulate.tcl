# simulate.tcl
open_project ./vivado_project/sentinel_ip_core.xpr

add_files -fileset sim_1 -norecurse ../sim/tb_sentinel_ip_core.v
set_property top tb_sentinel_ip_core [get_filesets sim_1]

launch_simulation
run all
puts "Simulation completed."
