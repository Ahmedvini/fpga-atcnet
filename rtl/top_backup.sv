module top #(
    parameter int DATA_WIDTH  = 16,
    parameter int COEF_WIDTH  = 16,
    parameter int ACC_WIDTH   = 48,
    parameter int WINDOW_SIZE = 32,
    parameter int KERNEL_SIZE = 5,
    parameter int NUM_CH      = 1, 
    
    parameter logic signed [COEF_WIDTH-1:0] CONV_COEFFS_A [0:KERNEL_SIZE-1] = '{default: 0},
    parameter logic signed [COEF_WIDTH-1:0] CONV_COEFFS_B [0:KERNEL_SIZE-1] = '{default: 0},
    parameter logic signed [COEF_WIDTH-1:0] SCALE_FACTORS [0:NUM_CH-1] = '{default: 0}
) (
    input  logic clk,
    input  logic rst,

    input  logic signed [DATA_WIDTH-1:0] in_sample,
    input  logic                         in_valid,

    // dont_touch ensures Vivado keeps this logic for your utilization report
    (* dont_touch = "true" *) output logic signed [DATA_WIDTH-1:0] out_sample,
    (* dont_touch = "true" *) output logic                         out_valid
);

    // --- Signals ---
    logic signed [DATA_WIDTH-1:0] win_data [0:WINDOW_SIZE-1]; 
    logic                         win_valid;
    logic signed [DATA_WIDTH-1:0] stream_data;
    logic                         stream_valid;
    logic signed [DATA_WIDTH-1:0] feature_out;
    logic                         feature_valid;
    logic signed [DATA_WIDTH-1:0] scale_in [0:NUM_CH-1];
    logic signed [DATA_WIDTH-1:0] scale_out [0:NUM_CH-1];
    logic                         scale_valid;

    // 1. Window Generation
    window_gen #(
        .DATA_W(DATA_WIDTH),
        .WINDOW_SIZE(WINDOW_SIZE)
    ) u_window_gen (
        .clk(clk),
        .rst(rst),
        .in_valid(in_valid),
        .in_sample(in_sample),
        .window_valid(win_valid),
        .window(win_data) 
    );

    // 2. Window Reader
    window_reader #(
        .DATA_WIDTH(DATA_WIDTH),
        .WINDOW_SIZE(WINDOW_SIZE)
    ) u_window_reader (
        .clk(clk),
        .rst(rst),
        .window_in(win_data), 
        .window_valid(win_valid),
        .stream_out(stream_data),
        .stream_valid(stream_valid)
    );

    // 3. Feature Extraction
    dual_branch_conv #(
        .DATA_WIDTH(DATA_WIDTH),
        .COEF_WIDTH(COEF_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .KERNEL_SIZE(KERNEL_SIZE),
        .COEFFS_A(CONV_COEFFS_A),
        .COEFFS_B(CONV_COEFFS_B)
    ) u_feat_extract (
        .clk(clk),
        .rst(rst),
        .x_in(stream_data),
        .x_valid(stream_valid),
        .y_out(feature_out),
        .y_valid(feature_valid)
    );

    // 4. Channel Scale
    assign scale_in[0] = feature_out;

    channel_scale #(
        .DATA_WIDTH(DATA_WIDTH),
        .COEF_WIDTH(COEF_WIDTH),
        .NUM_CH(NUM_CH),
        .SCALE(SCALE_FACTORS)
    ) u_channel_scale (
        .clk(clk),
        .rst(rst),
        .x_in(scale_in),
        .x_valid(feature_valid),
        .y_out(scale_out),
        .y_valid(scale_valid)
    );

    assign out_sample = scale_out[0];
    assign out_valid  = scale_valid;

endmodule