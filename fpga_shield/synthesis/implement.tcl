# implement.tcl
open_project ./vivado_project/sentinel_ip_core.xpr

wait_on_run synth_1

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

open_run impl_1
report_utilization -file ./reports/impl_utilization.rpt
report_timing_summary -file ./reports/impl_timing.rpt
report_power -file ./reports/power.rpt

puts "Implementation completed."
