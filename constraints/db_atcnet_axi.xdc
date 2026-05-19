# =============================================================================
# db_atcnet_axi.xdc  —  Constraints for the DB-ATCNet deployment block on
# ZCU104 (XCZU7EV-2FFVC1156).
#
# Target use:
#   * Out-of-context synthesis  (default — used by synth/synth_fit.tcl).
#     IOBs are NOT inserted; the design synthesizes as a block ready for
#     IPI integration. Only the clock constraint applies.
#
#   * In-context bring-up.  When db_atcnet_axi is dropped into a Vivado IPI
#     block design with the Zynq PS, all s_axi / s_axis / irq_done ports are
#     internally connected and NO pin assignments are needed. The clock
#     constraint stays valid (sourced by the PS PL_CLK0).
#
# The 10,520-Bonded-IOB blowup from a naive flat synthesis of a top with
# many AXI ports is avoided by:
#   - keeping the design out-of-context, OR
#   - wrapping it in an IPI block design with the PS for in-context flow.
# Do NOT run "Run Synthesis" from the Vivado GUI against db_atcnet_axi as
# a top-level project — those AXI ports would each pull an IOB.
# =============================================================================

# ---------------------------------------------------------------------------
# Primary clock — 100 MHz on `clk`. For ZCU104, PL_CLK0 from the PS is the
# canonical source; the IPI block design forwards it here.
# ---------------------------------------------------------------------------
create_clock -name clk -period 10.000 [get_ports clk]

# ---------------------------------------------------------------------------
# Input/output delay defaults so the timing engine doesn't flag every AXIS
# / AXI-Lite port as unconstrained when run out-of-context.
# ---------------------------------------------------------------------------
set_input_delay  -clock [get_clocks clk] -max 2.0 [get_ports {s_axi_*}]
set_input_delay  -clock [get_clocks clk] -min 0.5 [get_ports {s_axi_*}]
set_output_delay -clock [get_clocks clk] -max 2.0 [get_ports {s_axi_*}]
set_output_delay -clock [get_clocks clk] -min 0.5 [get_ports {s_axi_*}]

set_input_delay  -clock [get_clocks clk] -max 2.0 [get_ports {s_axis_*}]
set_input_delay  -clock [get_clocks clk] -min 0.5 [get_ports {s_axis_*}]
set_output_delay -clock [get_clocks clk] -max 2.0 [get_ports {s_axis_*}]
set_output_delay -clock [get_clocks clk] -min 0.5 [get_ports {s_axis_*}]

set_output_delay -clock [get_clocks clk] -max 2.0 [get_ports irq_done]
set_output_delay -clock [get_clocks clk] -min 0.5 [get_ports irq_done]

# ---------------------------------------------------------------------------
# Reset is asynchronous — declare to the timing engine.
# ---------------------------------------------------------------------------
set_input_delay  -clock [get_clocks clk] -max 2.0 [get_ports rst]
set_input_delay  -clock [get_clocks clk] -min 0.5 [get_ports rst]
set_false_path -from [get_ports rst] -to [all_registers]

# ---------------------------------------------------------------------------
# Resource attributes — encourage Vivado to map the large weight RAMs and
# the ECA₁ replay buffer to BRAM/URAM rather than distributed registers.
# These are HINTs; the synth tool will pick the actual primitive.
# ---------------------------------------------------------------------------
# ECA₁ pipeline replay buffer (~96 KB).
set_property RAM_STYLE block [get_cells -hierarchical -filter {NAME =~ *eca1*buf_mem_reg*}] -quiet
set_property RAM_STYLE block [get_cells -hierarchical -filter {NAME =~ *pre_conv_buf_reg*}] -quiet
set_property RAM_STYLE block [get_cells -hierarchical -filter {NAME =~ *post_conv_buf_reg*}] -quiet
# Large TCFN weight banks (5 windows × 4 conv1d × ~4 KB each) — URAM-friendly.
set_property RAM_STYLE ultra [get_cells -hierarchical -filter {NAME =~ *u_top/u_window/u_tcfn/W*_reg*}] -quiet
set_property RAM_STYLE ultra [get_cells -hierarchical -filter {NAME =~ *u_top/u_window/u_tcfn/B*_reg*}] -quiet

# ---------------------------------------------------------------------------
# False paths for the AXI-Lite weight loader writes — single-write
# transactions that don't need single-cycle timing closure.
# ---------------------------------------------------------------------------
# (Add here once the post-synth report shows specific cross-domain warnings.)
