# synth_top.tcl
# Synthesis script for TOTAL Shield on Arty A7-100T

set project_name "total_shield_synth"
set project_dir "./vivado_project"
set part "xc7a100tcsg324-1"   # Arty A7-100T
# Для Arty A7-35T используйте: xc7a35ticsg324-1l
# Для VCU118: xcvu9p-flga2104-2L-e

# Создать проект
create_project -force $project_name $project_dir -part $part
set_property target_language Verilog [current_project]

# Добавить все исходные Verilog файлы из ../rtl
set rtl_files [glob -nocomplain ../rtl/*.v]
if {[llength $rtl_files] == 0} {
    error "No Verilog files found in ../rtl"
}
add_files -norecurse $rtl_files

# Добавить include-файл (tree_nodes_unified.vh) - не как отдельный модуль, но чтобы он был доступен
# В Vivado include путь задаётся через `incdir`
set_property include_dirs [list ../rtl] [current_fileset]

# Если есть констрейнты, добавить
set constr_file "../constraints/arty_a7.xdc"
if {[file exists $constr_file]} {
    add_files -fileset constrs_1 -norecurse $constr_file
    puts "Constraints file added: $constr_file"
} else {
    puts "Warning: No constraints file found. Timing report may be incomplete."
}

# Установить топ-модуль
set_property top sentinel_ip_core_top [current_fileset]

# Запустить синтез
puts "Starting synthesis..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Открыть синтезированный дизайн для генерации отчётов
open_run synth_1

# Создать папку для отчётов
file mkdir ./synth_reports

# Отчёт по использованию ресурсов
report_utilization -file ./synth_reports/utilization.rpt
puts "Utilization report saved to ./synth_reports/utilization.rpt"

# Отчёт по таймингам (worst paths)
report_timing_summary -file ./synth_reports/timing_summary.rpt
puts "Timing summary saved to ./synth_reports/timing_summary.rpt"

# Отчёт по мощности (приблизительный)
report_power -file ./synth_reports/power.rpt
puts "Power estimate saved to ./synth_reports/power.rpt"

# Дополнительно: отчёт по тактовым доменам
report_clock_networks -file ./synth_reports/clock_networks.rpt

puts "Synthesis completed. Reports are in ./synth_reports"
