/**
 * Module: dual_branch_conv
 * 
 * Description:
 *   Implements a dual-branch convolution structure.
 *   Contains two parallel `temporal_conv` blocks (Branch A and Branch B)
 *   fed by the same input stream.
 *   
 *   Output = (Branch_A_Output + Branch_B_Output)
 *   
 *   To preserve dynamic range, we perform MSB extraction on the sum.
 *   Summation width is DATA_WIDTH + 1.
 *   One output register stage is added after summation.
 * 
 * Latency:
 *   temporal_conv latency (2 cycles) + 1 cycle summation reg = 3 cycles.
 */

module dual_branch_conv #(
    parameter int DATA_WIDTH  = 16,
    parameter int COEF_WIDTH  = 16,
    parameter int ACC_WIDTH   = 48,
    parameter int KERNEL_SIZE = 5,
    parameter logic signed [COEF_WIDTH-1:0] COEFFS_A [KERNEL_SIZE] = '{default: 0},
    parameter logic signed [COEF_WIDTH-1:0] COEFFS_B [KERNEL_SIZE] = '{default: 0}
) (
    input  logic clk,
    input  logic rst,

    // Streaming Input
    input  logic signed [DATA_WIDTH-1:0] x_in,
    input  logic                         x_valid,

    // Streaming Output
    output logic signed [DATA_WIDTH-1:0] y_out,
    output logic                         y_valid
);

    // -------------------------------------------------------------------------
    // Signal Declarations
    // -------------------------------------------------------------------------

    // Branch A Signals
    logic signed [DATA_WIDTH-1:0] out_a;
    logic                         valid_a;

    // Branch B Signals
    logic signed [DATA_WIDTH-1:0] out_b;
    logic                         valid_b;

    // Summation Signals
    // Sum needs 1 extra bit to avoid overflow before slicing
    logic signed [DATA_WIDTH:0] sum_comb; 
    
    // Internal Valid signal
    logic valid_comb;

    // -------------------------------------------------------------------------
    // Module Instantiations
    // -------------------------------------------------------------------------

    // Branch A
    temporal_conv #(
        .DATA_WIDTH(DATA_WIDTH),
        .COEF_WIDTH(COEF_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .KERNEL_SIZE(KERNEL_SIZE),
        .COEFFS(COEFFS_A)
    ) u_branch_a (
        .clk(clk),
        .rst(rst),
        .x_in(x_in),
        .x_valid(x_valid),
        .y_out(out_a),
        .y_valid(valid_a)
    );

    // Branch B
    temporal_conv #(
        .DATA_WIDTH(DATA_WIDTH),
        .COEF_WIDTH(COEF_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .KERNEL_SIZE(KERNEL_SIZE),
        .COEFFS(COEFFS_B)
    ) u_branch_b (
        .clk(clk),
        .rst(rst),
        .x_in(x_in),
        .x_valid(x_valid),
        .y_out(out_b),
        .y_valid(valid_b)
    );

    // -------------------------------------------------------------------------
    // Combinational Summation
    // -------------------------------------------------------------------------
    
    always_comb begin
        // Sign-extend inputs to DATA_WIDTH+1 and sum
        sum_comb = signed'(out_a) + signed'(out_b);
        
        // Output is valid only if both branches are valid
        valid_comb = valid_a && valid_b;
    end

    // -------------------------------------------------------------------------
    // Output Registration (MSB Extraction)
    // -------------------------------------------------------------------------

    always_ff @(posedge clk) begin
        if (rst) begin
            y_out   <= '0;
            y_valid <= 1'b0;
        end else begin
            y_valid <= valid_comb;
            
            if (valid_comb) begin
                // MSB Extraction to preserve dynamic range.
                // We take the top DATA_WIDTH bits of the (DATA_WIDTH+1)-bit sum.
                // Effectively dividing by 2 (arithmetic shift right).
                // Indexing: [DATA_WIDTH : 1]
                y_out <= sum_comb[DATA_WIDTH : 1];
            end
        end
    end

endmodule
