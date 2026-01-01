/**
 * Module: top
 * 
 * Description:
 *   Structural integration of the FPGA ML Accelerator submodules.
 *   Dataflow: window_gen -> temporal_conv -> channel_scale.
 *   
 *   This module demonstrates a single-channel processing pipeline.
 *   It wires submodules together without adding new processing logic.
 * 
 * Latency:
 *   Driven by submodule latencies.
 *   window_gen: 0 cycles (combinational output from FF buffer) effectively throughput matched.
 *   temporal_conv: 2 cycles.
 *   channel_scale: 1 cycle.
 *   Total pipeline latency: ~3 cycles from window_valid to out_valid.
 */

module top #(
    parameter int DATA_WIDTH  = 16,
    parameter int COEF_WIDTH  = 16,
    parameter int ACC_WIDTH   = 48,
    parameter int WINDOW_SIZE = 32,
    parameter int KERNEL_SIZE = 5,
    parameter int NUM_CH      = 1, // Single channel pipeline
    
    // Parameters for coefficients need to be passable.
    // Simplifying assumption: These are passed or defaulted by submodules if not driven here.
    // For synthesis, we rely on submodule defaults or user overriding 'top' parameters.
    // Passing unpacked arrays of flexible size in top-level params can be tricky in some tools,
    // but SystemVerilog supports it.
    parameter logic signed [COEF_WIDTH-1:0] CONV_COEFFS [KERNEL_SIZE] = '{default: 0},
    parameter logic signed [COEF_WIDTH-1:0] SCALE_FACTORS [0:NUM_CH-1] = '{default: 0}
) (
    input  logic clk,
    input  logic rst,

    // Top-Level Streaming Input
    input  logic signed [DATA_WIDTH-1:0] in_sample,
    input  logic                         in_valid,

    // Top-Level Streaming Output
    output logic signed [DATA_WIDTH-1:0] out_sample,
    output logic                         out_valid
);

    // -------------------------------------------------------------------------
    // Signal Declarations
    // -------------------------------------------------------------------------

    // 1. Window Generation Outputs
    logic [DATA_WIDTH-1:0] win_data [0:WINDOW_SIZE-1];
    logic                  win_valid;

    // 2. Temporal Convolution Outputs
    logic signed [DATA_WIDTH-1:0] conv_out;
    logic                         conv_valid;

    // 3. Channel Scale Inputs/Outputs
    // channel_scale expects array input. We map the scalar conv_out to an array of size 1.
    logic signed [DATA_WIDTH-1:0] scale_in [0:NUM_CH-1];
    logic signed [DATA_WIDTH-1:0] scale_out [0:NUM_CH-1];
    logic                         scale_valid;

    // -------------------------------------------------------------------------
    // Module Instantiation
    // -------------------------------------------------------------------------

    // 1. Window Generation
    // Collects streaming samples into a sliding window.
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

    // 2. Temporal Convolution
    // Performs 1D convolution on the stream.
    // We connect the NEWEST sample from the window to the convolution input.
    // NOTE: temporal_conv has its own internal shift register (history).
    // So we just feed it the stream of new valid samples coming out of window_gen.
    // The 'win_data' is updated every time 'win_valid' is high.
    // Assuming 'win_data[WINDOW_SIZE-1]' is the newest sample (based on window_gen logic: wr_ptr+i).
    // Actually, let's verify window_gen ordering:
    // idx = wr_ptr + i. i=0 is oldest? i=WINDOW_SIZE-1 is newest.
    // We feed the newest sample to keep the stream going.
    
    temporal_conv #(
        .DATA_WIDTH(DATA_WIDTH),
        .COEF_WIDTH(COEF_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .KERNEL_SIZE(KERNEL_SIZE),
        .COEFFS(CONV_COEFFS)
    ) u_temporal_conv (
        .clk(clk),
        .rst(rst),
        .x_in(signed'(win_data[WINDOW_SIZE-1])), // Cast to signed if needed, though port is signed
        .x_valid(win_valid),
        .y_out(conv_out),
        .y_valid(conv_valid)
    );

    // 3. Channel Scale
    // Scales the convolution result.
    // Map scalar -> array -> scalar.
    
    assign scale_in[0] = conv_out;

    channel_scale #(
        .DATA_WIDTH(DATA_WIDTH),
        .COEF_WIDTH(COEF_WIDTH),
        .NUM_CH(NUM_CH), // Should be 1
        .SCALE(SCALE_FACTORS)
    ) u_channel_scale (
        .clk(clk),
        .rst(rst),
        .x_in(scale_in),
        .x_valid(conv_valid),
        .y_out(scale_out),
        .y_valid(scale_valid)
    );

    // -------------------------------------------------------------------------
    // Output Assignments
    // -------------------------------------------------------------------------
    
    assign out_sample = scale_out[0];
    assign out_valid  = scale_valid;

endmodule
