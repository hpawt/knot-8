# DEV190806037 has a 50 MHz oscillator connected to FPGA pin 91.
create_clock -name FPGA_CLK -period 20.000 [get_ports {FPGA_CLK}]
derive_clock_uncertainty

# The physical buttons are asynchronous. The reset input is asynchronously
# asserted and synchronously released in knot8_board.v; the user buttons are sampled
# only through the memory-mapped input register.
set_false_path -from [get_ports {BUTTON_S2_N}]
set_false_path -from [get_ports {BUTTON_S3_N}]
set_false_path -from [get_ports {BUTTON_S4_N}]

# CH340E receive data is asynchronous to FPGA_CLK and passes through a
# two-flip-flop synchronizer in uart_rx. UART_TX is sampled by the CH340E from
# its own baud clock.
set_false_path -from [get_ports {FPGA_RX}]
set_false_path -to [get_ports {FPGA_TX}]

# LEDs are human-visible status outputs and are not sampled by another
# clocked device, so there is no external setup/hold requirement.
set_false_path -to [get_ports {LED_N[*]}]
