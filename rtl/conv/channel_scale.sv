/**
 * Module: channel_scale
 * 
 * Description:
 *   Implements a static per-channel scaling factor for a streaming input vector.
 *   y[i] = x[i] * SCALE[i]
 *   
 *   This module is useful for feature normalization or fixed-point rescaling.
 *   It uses MSB extraction to preserve dynamic range after multiplication.
 * 
 * Latency:
 *   1 cycle. Input is registered producing the output.
 *   y_valid follows x_valid by 1 cycle.
 * 
 * Parameters:
 *   DATA_WIDTH - Width of input and output samples (default: 16)
 *   COEF_WIDTH - Width of scaling coefficients (default: 16)
 *   NUM_CH     - Number of channels (default: 4)
 *   SCALE      - Array of coefficients, one per channel.
 */

module channel_scale #(
    parameter int DATA_WIDTH = 16,
    parameter int COEF_WIDTH = 16,
    parameter int NUM_CH     = 4,
    parameter logic signed [COEF_WIDTH-1:0] SCALE [0:NUM_CH-1] = '{default: 0}
) (
    input  logic clk,
    input  logic rst,

    // Streaming Input
    input  logic signed [DATA_WIDTH-1:0] x_in [0:NUM_CH-1],
    input  logic                         x_valid,

    // Streaming Output
    output logic signed [DATA_WIDTH-1:0] y_out [0:NUM_CH-1],
    output logic                         y_valid
);

    // -------------------------------------------------------------------------
    // Signal Definitions
    // -------------------------------------------------------------------------
    
    // Internal product width: DATA_WIDTH + COEF_WIDTH
    localparam int PROD_WIDTH = DATA_WIDTH + COEF_WIDTH;

    // Intermediate product signals declared at module level for synthesis safety
    logic signed [PROD_WIDTH-1:0] product [0:NUM_CH-1];

    // -------------------------------------------------------------------------
    // Combinational Logic: Multiplication
    // -------------------------------------------------------------------------
    
    always_comb begin
        for (int i = 0; i < NUM_CH; i++) begin
            product[i] = x_in[i] * SCALE[i];
        end
    end

    // -------------------------------------------------------------------------
    // Sequential Logic: Output Registration & Valid Propagation
    // -------------------------------------------------------------------------
    
    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < NUM_CH; i++) begin
                y_out[i] <= '0;
            end
            y_valid <= 1'b0;
        end else begin
            // Valid propagation
            y_valid <= x_valid;

            // Update output register
            // We use the combinatorial product result.
            // If x_valid is low, we can still update or hold. 
            // To maintain strictly clean data we update when x_valid is high.
            if (x_valid) begin
                for (int i = 0; i < NUM_CH; i++) begin
                    // MSB Extraction: Take the top DATA_WIDTH bits
                    y_out[i] <= product[i][PROD_WIDTH-1 -: DATA_WIDTH];
                end
            end
        end
    end

endmodule
