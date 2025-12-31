# ModelSim/QuestaSim DO file for temporal_conv_tb
# Run with: vsim -do run_temporal_conv_tb.do

# Create work library if it doesn't exist
if {![file exists work]} {
    vlib work
}

# Compile SystemVerilog files
vlog -sv +define+SIMULATION ../rtl/conv/temporal_conv.sv
vlog -sv +define+SIMULATION temporal_conv_tb.sv

# Load testbench
vsim -voptargs=+acc work.temporal_conv_tb

# Add waves
add wave -divider "Clock & Reset"
add wave -color "yellow" /temporal_conv_tb/clk
add wave -color "red" /temporal_conv_tb/rst_n

add wave -divider "Input Interface"
add wave -radix decimal /temporal_conv_tb/data_in
add wave -color "green" /temporal_conv_tb/data_in_valid

add wave -divider "Output Interface"
add wave -radix decimal /temporal_conv_tb/data_out
add wave -color "green" /temporal_conv_tb/data_out_valid

add wave -divider "Test Control"
add wave -radix decimal /temporal_conv_tb/test_num
add wave -radix decimal /temporal_conv_tb/pass_count
add wave -radix decimal /temporal_conv_tb/error_count
add wave -radix decimal /temporal_conv_tb/cycle_count

add wave -divider "DUT Internal (if accessible)"
# add wave /temporal_conv_tb/dut/*

# Configure wave window
configure wave -namecolwidth 250
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2

# Run simulation
run -all

# Zoom to fit
wave zoom full

# Keep window open
#quit -sim
