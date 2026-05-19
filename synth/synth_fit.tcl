# =============================================================================
# synth_fit.tcl  —  Vivado synthesis + resource-utilization report for
# the DB-ATCNet deployment block on both Z-7020 and Zynq Ultrascale+ KU3P.
#
# Usage:  vivado -mode batch -source synth/synth_fit.tcl -tclargs <part>
#         where <part> ∈ {xc7z020clg400-1, xczu3eg-sbva484-1-e}
#
# Outputs (in build/synth_<part>/):
#   utilization.txt    — LUT/FF/DSP/BRAM totals
#   timing.txt         — worst-case-slack report (rough)
#   synth.log          — full Vivado log
# =============================================================================

if {[llength $argv] != 1} {
    puts "Usage: vivado -mode batch -source synth/synth_fit.tcl -tclargs <part>"
    exit 1
}

set part [lindex $argv 0]
set top  db_atcnet_axi
set repo [file normalize [pwd]]
set out  $repo/build/synth_$part
file mkdir $out

create_project -in_memory -part $part

# Add all RTL.
set rtl_files [list \
    rtl/util/serial_divider.sv \
    rtl/conv/conv2d_temporal.sv \
    rtl/conv/depthwise_spatial.sv \
    rtl/conv/elu.sv \
    rtl/conv/avg_pool_time.sv \
    rtl/conv/conv1d_temporal.sv \
    rtl/conv/conv1d_temporal_tm.sv \
    rtl/conv/sat_add.sv \
    rtl/conv/tcfn.sv \
    rtl/conv/branch_pipeline.sv \
    rtl/attention/eca_attention.sv \
    rtl/attention/gap_accumulator.sv \
    rtl/attention/gate_apply.sv \
    rtl/attention/cbam_channel_attn.sv \
    rtl/attention/cbam_spatial_attn.sv \
    rtl/attention/eca1_pipeline.sv \
    rtl/classifier/dense_classifier.sv \
    rtl/classifier/output_head.sv \
    rtl/window/gumbel_channel_adapter.sv \
    rtl/weights/axi_lite_weight_loader.sv \
    rtl/weights/weight_bank.sv \
    rtl/db_atcnet_window_pipeline.sv \
    rtl/db_atcnet_post_eca1.sv \
    rtl/db_atcnet_conv2d_eca1.sv \
    rtl/db_atcnet_top.sv \
    rtl/db_atcnet_axi.sv \
]
foreach f $rtl_files { add_files -norecurse $f }

# Pin file paths to absolute so $readmemh works during synthesis.
set_property file_type SystemVerilog [get_files *.sv]

# Synthesize. -mode out_of_context skips I/O buffer insertion so we don't
# need to constrain every clk/reset port to a physical pin.
synth_design -top $top -part $part -include_dirs $repo -mode out_of_context

# Now that a design exists, add a 100 MHz clock for the timing report.
create_clock -name clk -period 10.000 [get_ports clk]

# Reports.
report_utilization                 -file $out/utilization.txt
report_utilization -hierarchical   -file $out/utilization_hier.txt
report_timing_summary -delay_type min_max -report_unconstrained \
                                   -file $out/timing.txt

puts "==== Synthesis fit summary ($part) ===="
puts [exec head -80 $out/utilization.txt]
puts "..."
puts "(full reports in $out/)"

close_project
exit
