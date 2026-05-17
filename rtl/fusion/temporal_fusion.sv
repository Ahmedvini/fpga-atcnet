/**
 * Module: temporal_fusion
 * 
 * Description:
 *   Hardware-simplified temporal fusion network.
 *   Fuses multiple temporal feature streams into a single feature.
 *   
 *   Operation:
 *   1. Each input stream is processed by a dedicated lightweight temporal convolution (FIR).
 *   2. The outputs of these convolutions are summed (fused).
 *   3. The result is registered output, effectively projecting the multi-stream input 
 *      to a single temporal feature.
 * 
 *   Input:  [NUM_STREAMS] (Each is a stream of samples)
 *   Output: Scalar sample
 * 
 * Latency:
 *   temporal_conv (2 cycles) + Summation Register (1 cycle) = 3 cycles.
 */

module temporal_fusion #(
    parameter int DATA_WIDTH  = 16,
    parameter int COEF_WIDTH  = 16,
    parameter int ACC_WIDTH   = 48,
    parameter int KERNEL_SIZE = 5,
    parameter int NUM_STREAMS = 4,
    // 2D Array of coefficients: [NUM_STREAMS][KERNEL_SIZE]
    parameter logic signed [COEF_WIDTH-1:0] COEFFS [0:NUM_STREAMS-1][KERNEL_SIZE] = '{default: 0}
) (
    input  logic clk,
    input  logic rst,

    // Streaming Inputs (Vector of inputs)
    input  logic signed [DATA_WIDTH-1:0] x_in [0:NUM_STREAMS-1],
    input  logic                         x_valid,

    // Streaming Output
    output logic signed [DATA_WIDTH-1:0] y_out,
    output logic                         y_valid
);

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    
    // Summation width to avoid overflow before final scaling
    localparam int SUM_WIDTH = DATA_WIDTH + $clog2(NUM_STREAMS);

    // -------------------------------------------------------------------------
    // Signal Declarations
    // -------------------------------------------------------------------------

    // Convolution Outputs
    logic signed [DATA_WIDTH-1:0] conv_out   [0:NUM_STREAMS-1];
    logic                         conv_valid [0:NUM_STREAMS-1];

    // Summation Logic
    logic signed [SUM_WIDTH-1:0]  sum_comb;
    logic                         valid_comb;

    // -------------------------------------------------------------------------
    // Parallel Convolutions
    // -------------------------------------------------------------------------

    genvar i;
    generate
        for (i = 0; i < NUM_STREAMS; i++) begin : gen_conv
            temporal_conv #(
                .DATA_WIDTH(DATA_WIDTH),
                .COEF_WIDTH(COEF_WIDTH),
                .ACC_WIDTH(ACC_WIDTH),
                .KERNEL_SIZE(KERNEL_SIZE),
                // Pass slice of 2D array: COEFFS[i]
                .COEFFS(COEFFS[i])
            ) u_conv (
                .clk(clk),
                .rst(rst),
                .x_in(x_in[i]),
                .x_valid(x_valid),
                .y_out(conv_out[i]),
                .y_valid(conv_valid[i])
            );
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Fusion (Summation)
    // -------------------------------------------------------------------------
    
    // Combinational Sum
    always_comb begin
        sum_comb = '0;
        // Check validity: Requires all streams valid. 
        // Since they share x_valid and identical conv pipelines, checking index 0 is sufficient,
        // but ANDing them is safer structurally.
        valid_comb = conv_valid[0]; 
        
        for (int j = 0; j < NUM_STREAMS; j++) begin
            sum_comb = sum_comb + conv_out[j];
            // valid_comb = valid_comb & conv_valid[j]; // Redundant if fully sync, but formal correct
        end
    end

    // -------------------------------------------------------------------------
    // Output Registration
    // -------------------------------------------------------------------------

    always_ff @(posedge clk) begin
        if (rst) begin
            y_out   <= '0;
            y_valid <= 1'b0;
        end else begin
            y_valid <= valid_comb;
            
            if (valid_comb) begin
                // MSB Extraction / Normalization
                // We extract the top DATA_WIDTH bits to preserve dynamic range
                // (Approximating averaging/normalization of the sum)
                // Use part-select with proper width.
                y_out <= sum_comb[SUM_WIDTH-1 -: DATA_WIDTH];
            end
        end
    end

endmodule
