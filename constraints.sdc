# 1. Define the 50 MHz ideal clock (20ns period)
create_clock -name clk_50mhz -period 20.0 [get_ports clk_50mhz]

# 2. Derive clock uncertainty (Required by Quartus for FPGA jitter)
derive_clock_uncertainty

# 3. Set asynchronous reset as a false path
set_false_path -from [get_ports rst_n]