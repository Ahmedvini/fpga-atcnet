// =============================================================================
// db_atcnet_axi_v.v — Plain Verilog wrapper around the SystemVerilog
// db_atcnet_axi module so it can be added to a Vivado IPI block design as a
// Module Reference (IPI Module Reference rejects .sv files as the top).
//
// All ports pass through 1:1. Generic *_FILE parameters are inherited from
// the inner module's defaults (which the project's Generics/Parameters
// override sets via set_property generic on the fileset).
// =============================================================================

`timescale 1ns / 1ps

module db_atcnet_axi_v #(
    parameter AXIS_TDATA_W = 32,
    parameter AXI_ADDR_W   = 32,
    parameter AXI_DATA_W   = 32
) (
    input  wire                       clk,
    input  wire                       rst,

    input  wire [AXIS_TDATA_W-1:0]    s_axis_tdata,
    input  wire                       s_axis_tvalid,
    output wire                       s_axis_tready,
    input  wire                       s_axis_tlast,

    input  wire [AXI_ADDR_W-1:0]      s_axi_awaddr,
    input  wire                       s_axi_awvalid,
    output wire                       s_axi_awready,
    input  wire [AXI_DATA_W-1:0]      s_axi_wdata,
    input  wire [AXI_DATA_W/8-1:0]    s_axi_wstrb,
    input  wire                       s_axi_wvalid,
    output wire                       s_axi_wready,
    output wire [1:0]                 s_axi_bresp,
    output wire                       s_axi_bvalid,
    input  wire                       s_axi_bready,
    input  wire [AXI_ADDR_W-1:0]      s_axi_araddr,
    input  wire                       s_axi_arvalid,
    output wire                       s_axi_arready,
    output wire [AXI_DATA_W-1:0]      s_axi_rdata,
    output wire [1:0]                 s_axi_rresp,
    output wire                       s_axi_rvalid,
    input  wire                       s_axi_rready,

    output wire                       irq_done
);

    db_atcnet_axi #(
        .AXIS_TDATA_W (AXIS_TDATA_W),
        .AXI_ADDR_W   (AXI_ADDR_W),
        .AXI_DATA_W   (AXI_DATA_W)
    ) u_inst (
        .clk            (clk),
        .rst            (rst),

        .s_axis_tdata   (s_axis_tdata),
        .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tready  (s_axis_tready),
        .s_axis_tlast   (s_axis_tlast),

        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),
        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),
        .s_axi_rdata    (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready),

        .irq_done       (irq_done)
    );

endmodule
