# generate_bitstream.tcl
open_project ./vivado_project/sentinel_ip_core.xpr

if {[get_runs impl_1 -quiet] == ""} {
    puts "Error: impl_1 run not found. Run implementation first."
    exit 1
}
wait_on_run impl_1

if {[file exists [get_property BITSTREAM_FILE [get_runs impl_1]]] == 0} {
    launch_runs impl_1 -to_step write_bitstream
    wait_on_run impl_1
}

set bitstream_file [get_property BITSTREAM_FILE [get_runs impl_1]]
file copy -force $bitstream_file ../output/sentinel_ip_core.bit
puts "Bitstream copied to ../output/sentinel_ip_core.bit"
