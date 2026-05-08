# arty_a7.xdc
# Constraints for TOTAL Shield on Digilent Arty A7-100T

# Clock: on-board 100 MHz
set_property PACKAGE_PIN E3 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name sys_clk [get_ports clk]

# Reset (active high) – use centre button (BTNU)
set_property PACKAGE_PIN T5 [get_ports rst]
set_property IOSTANDARD LVCMOS33 [get_ports rst]

# Attack alarm output – connect to LD4 (red LED)
set_property PACKAGE_PIN H5 [get_ports attack_alarm]
set_property IOSTANDARD LVCMOS33 [get_ports attack_alarm]

# NMI trigger output – connect to PMOD JD pin 1 (or any GPIO)
set_property PACKAGE_PIN H6 [get_ports trigger_nmi]
set_property IOSTANDARD LVCMOS33 [get_ports trigger_nmi]

# Zeroize command output – connect to PMOD JD pin 2
set_property PACKAGE_PIN J4 [get_ports zeroize_command]
set_property IOSTANDARD LVCMOS33 [get_ports zeroize_command]

# Zeroize done input – connect to switch (SW0) for simulation
set_property PACKAGE_PIN A8 [get_ports zeroize_done]
set_property IOSTANDARD LVCMOS33 [get_ports zeroize_done]

# Optional: security token (64-bit) – use PMOD connectors or hard‑code in test
# For real implementation, you might read from eFUSE or external key.
# Here we just tie to constant inside testbench.

# AXI4-Lite (optional) – if you use an embedded ARM core, connect to appropriate pins.
# By default, Arty A7 does not have an AXI master; we can use an internal AXI VIP in simulation.
# For hardware, you can route AXI to PMODs (slow) or use a soft-core MicroBlaze.
