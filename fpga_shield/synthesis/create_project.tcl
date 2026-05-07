# create_project.tcl
set project_name "sentinel_ip_core"
set project_dir "./vivado_project"
set part "xc7a100tcsg324-1"   # Arty A7 (XC7A100T)

create_project -force $project_name $project_dir -part $part

# Добавление RTL-файлов
add_files -norecurse [glob ../rtl/*.v]
add_files -norecurse [glob ../rtl/*.sv]

# Добавление констрейнтов (если есть)
set constr_file "../constraints/arty_a7.xdc"
if {[file exists $constr_file]} {
    add_files -fileset constrs_1 -norecurse $constr_file
}

# Топ-модуль
set_property top sentinel_ip_core [current_fileset]

save_project
puts "Project created: $project_dir/$project_name.xpr"
