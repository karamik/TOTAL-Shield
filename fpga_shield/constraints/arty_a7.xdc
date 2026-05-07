# Clock: 100 MHz (на плате Arty A7)
create_clock -period 10.000 -name sys_clk [get_ports clk]

# Reset (кнопка)
set_property PACKAGE_PIN R3 [get_ports rst]
set_property IOSTANDARD LVCMOS33 [get_ports rst]

# Индикация тревоги (LED)
set_property PACKAGE_PIN H5 [get_ports attack_alarm]
set_property IOSTANDARD LVCMOS33 [get_ports attack_alarm]

# NMI выход (PMOD)
set_property PACKAGE_PIN H6 [get_ports trigger_nmi]
set_property IOSTANDARD LVCMOS33 [get_ports trigger_nmi]

# Опционально: AXI4-Lite интерфейс (если используется внешний процессор)
# (пины зависят от вашей разводки, здесь пример для PMOD)
# ...
