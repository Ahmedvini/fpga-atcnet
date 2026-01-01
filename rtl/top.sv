/**
 * Module: top
 * 
 * Description:
 *   Structural integration of the FPGA ML Accelerator (Hardware-Simplified ATCNet).
 *   
 *   Architecture:
 *     Input Stream -> Window Gen -> Window Reader -> Feature Extraction -> Channel Scale -> Output
 *   
 *   Active Feature Extraction Path:
 *     - Dual Branch Convolution (ATCNet inspired)
 *   
 *   Optional/Alternative Paths (Commented):
 *     - Baseline Temporal Convolution (temporal_conv)
 *     - Multi-Stream Fusion (temporal_fusion)
 *     - Multi-Head Attention (temporal_multihead_attention)
 * 
 * Latency:
 *   Submodule dependant.
 */

module top #(
    parameter int DATA_WIDTH  = 16,
    parameter int COEF_WIDTH  = 16,
    parameter int ACC_WIDTH   = 48,
    parameter int WINDOW_SIZE = 32,
    parameter int KERNEL_SIZE = 5,
    parameter int NUM_CH      = 1, // Single channel pipeline demo
    
    // Coefficients
    parameter logic signed [COEF_WIDTH-1:0] CONV_COEFFS_A [KERNEL_SIZE] = '{default: 0},
    parameter logic signed [COEF_WIDTH-1:0] CONV_COEFFS_B [KERNEL_SIZE] = '{default: 0},
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

    // 1. Window Generation
    logic [DATA_WIDTH-1:0] win_data [0:WINDOW_SIZE-1];
    logic                  win_valid;

    // 2. Window Reader (Stream Adapter)
    logic signed [DATA_WIDTH-1:0] stream_data;
    logic                         stream_valid;

    // 3. Feature Extraction Output
    logic signed [DATA_WIDTH-1:0] feature_out;
    logic                         feature_valid;

    // 4. Channel Scale Inputs/Outputs
    logic signed [DATA_WIDTH-1:0] scale_in [0:NUM_CH-1];
    logic signed [DATA_WIDTH-1:0] scale_out [0:NUM_CH-1];
    logic                         scale_valid;

    // -------------------------------------------------------------------------
    // Module Instantiation
    // -------------------------------------------------------------------------

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
    // Adapts window vector to scalar stream for convolution.
    window_reader #(
        .DATA_WIDTH(DATA_WIDTH),
        .WINDOW_SIZE(WINDOW_SIZE)
    ) u_window_reader (
        .clk(clk),
        .rst(rst),
        .window_in(signed'(win_data)), // Cast to signed array
        .window_valid(win_valid),
        .stream_out(stream_data),
        .stream_valid(stream_valid)
    );

    // 3. Feature Extraction (Active: Dual Branch Convolution)
    // Using dual-branch structure to mimic ATCNet's diverse feature extraction.
    
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

    // --- Optional / Alternative Feature Extractors (Commented Out) ---
    /*
    // Baseline Temporal Convolution
    temporal_conv #( ... ) u_baseline ( ... );

    // Temporal Fusion (Requires multiple streams, e.g. from multiple window readers or branches)
    temporal_fusion #( ... ) u_fusion ( ... );

    // Multi-Head Attention (Requires vector input, e.g. [NUM_CH])
    temporal_multihead_attention #( ... ) u_attn ( ... );
    */
    // ---------------------------------------------------------------

    // 4. Channel Scale
    // Scales the feature output. 
    // Mapping scalar feature to array for the single-channel pipeline.
    
    assign scale_in[0] = feature_out;

    channel_scale #(
        .DATA_WIDTH(DATA_WIDTH),
        .COEF_WIDTH(COEF_WIDTH),
        .NUM_CH(NUM_CH), // 1
        .SCALE(SCALE_FACTORS)
    ) u_channel_scale (
        .clk(clk),
        .rst(rst),
        .x_in(scale_in),
        .x_valid(feature_valid),
        .y_out(scale_out),
        .y_valid(scale_valid)
    );

    // -------------------------------------------------------------------------
    // Output Assignments
    // -------------------------------------------------------------------------
    
    assign out_sample = scale_out[0];
    assign out_valid  = scale_valid;

endmodule
