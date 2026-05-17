/**
 * Module: temporal_conv
 *
 * Description:
 *   Streaming 1D temporal convolution (FIR filter) in signed fixed-point.
 *   Computes y[n] = sum_{i=0..K-1} ( COEFFS[i] * x[n-i] ).
 *
 *   Numerical model: inputs and coefficients are signed Q(I).(FRAC_BITS)
 *   fixed-point. Internal accumulator runs at ACC_WIDTH bits. The output is
 *   rescaled back to DATA_WIDTH with arithmetic right-shift by FRAC_BITS and
 *   symmetric saturation, so it preserves both sign and dynamic range.
 *
 * Latency:
 *   2 cycles from x_valid to y_valid (shift register + output register).
 *
 * Parameters:
 *   DATA_WIDTH  - Width of input and output samples (default: 16)
 *   COEF_WIDTH  - Width of coefficients (default: 16)
 *   ACC_WIDTH   - Width of the internal accumulator (default: 48)
 *   KERNEL_SIZE - Number of filter taps (default: 5)
 *   FRAC_BITS   - Fractional bits in coefficients. For Q8.8 inputs * Q8.8
 *                 coefficients, the product is Q16.16; right-shifting by
 *                 FRAC_BITS=8 yields a Q8.8 result. Default: COEF_WIDTH/2.
 *   COEFFS      - Array of coefficients, index 0 corresponds to the most
 *                 recent sample x[n].
 */

module temporal_conv #(
    parameter int DATA_WIDTH  = 16,
    parameter int COEF_WIDTH  = 16,
    parameter int ACC_WIDTH   = 48,
    parameter int KERNEL_SIZE = 5,
    parameter int FRAC_BITS   = COEF_WIDTH/2,
    parameter logic signed [COEF_WIDTH-1:0] COEFFS [KERNEL_SIZE] = '{default: 0}
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
    // Signals
    // -------------------------------------------------------------------------
    logic signed [DATA_WIDTH-1:0] shift_reg [0:KERNEL_SIZE-1];
    logic                         valid_d;
    logic signed [ACC_WIDTH-1:0]  acc_comb;
    logic signed [ACC_WIDTH-1:0]  acc_shifted;
    logic signed [DATA_WIDTH-1:0] acc_sat;

    // Saturation bounds at the target DATA_WIDTH
    localparam logic signed [ACC_WIDTH-1:0] SAT_MAX =
        (ACC_WIDTH)'(((1 <<< (DATA_WIDTH-1)) - 1));
    localparam logic signed [ACC_WIDTH-1:0] SAT_MIN =
        -(ACC_WIDTH)'(1 <<< (DATA_WIDTH-1));

    // -------------------------------------------------------------------------
    // Shift Register
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < KERNEL_SIZE; i++) shift_reg[i] <= '0;
        end else if (x_valid) begin
            shift_reg[0] <= x_in;
            for (int i = 1; i < KERNEL_SIZE; i++) shift_reg[i] <= shift_reg[i-1];
        end
    end

    // -------------------------------------------------------------------------
    // MAC (combinational)
    //
    // shift_reg[i] and COEFFS[i] are both `logic signed`; SystemVerilog will
    // produce a signed product of width (DATA_WIDTH+COEF_WIDTH), and the assign
    // into `acc_comb` (signed, ACC_WIDTH) sign-extends correctly. We add
    // explicit $signed() to defend against tool-specific context promotion.
    // -------------------------------------------------------------------------
    always_comb begin
        acc_comb = '0;
        for (int i = 0; i < KERNEL_SIZE; i++) begin
            acc_comb = acc_comb + $signed(shift_reg[i]) * $signed(COEFFS[i]);
        end
    end

    // -------------------------------------------------------------------------
    // Rescale (arithmetic right-shift) + symmetric saturation
    // -------------------------------------------------------------------------
    always_comb begin
        acc_shifted = acc_comb >>> FRAC_BITS;
        if (acc_shifted > SAT_MAX)      acc_sat = SAT_MAX[DATA_WIDTH-1:0];
        else if (acc_shifted < SAT_MIN) acc_sat = SAT_MIN[DATA_WIDTH-1:0];
        else                            acc_sat = acc_shifted[DATA_WIDTH-1:0];
    end

    // -------------------------------------------------------------------------
    // Output registration (+ 2-stage valid pipeline)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            y_out   <= '0;
            y_valid <= 1'b0;
            valid_d <= 1'b0;
        end else begin
            valid_d <= x_valid;
            y_valid <= valid_d;
            if (valid_d) y_out <= acc_sat;
        end
    end

endmodule
