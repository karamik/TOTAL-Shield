# synthesize.tcl
open_project ./vivado_project/sentinel_ip_core.xpr

launch_runs synth_1
wait_on_run synth_1

open_run synth_1
report_utilization -file ./reports/synth_utilization.rpt
report_timing_summary -file ./reports/synth_timing.rpt

puts "Synthesis completed. Reports in ./reports/"
