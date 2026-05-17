/**
 * Module: temporal_conv
 * 
 * Description:
 *   Implements a streaming 1D temporal convolution (FIR filter) using fixed-point arithmetic.
 *   The module computes y[n] = sum_{i=0 to K-1} (coeff[i] * x[n-i]).
 *   
 * Latency:
 *   The design uses a shift register to store samples.
 *   Input `x_in` is registered into the shift register on the first cycle.
 *   The MAC operation effectively operates on the registered state.
 *   The output is registered.
 *   Total Latency: 2 cycles from x_in valid to y_out valid for the corresponding term.
 *     Cycle 0: x_in present, x_valid = 1
 *     Cycle 1: shift_reg updates.
 *     Cycle 2: y_out updates (capturing the sum).
 * 
 * Parameters:
 *   DATA_WIDTH  - Width of input and output samples (default: 16)
 *   COEF_WIDTH  - Width of coefficients (default: 16)
 *   ACC_WIDTH   - Width of the internal accumulator (default: 48)
 *   KERNEL_SIZE - Number of filter taps (default: 5)
 *   COEFFS      - Array of coefficients, index 0 corresponds to x[n] (most recent)
 */

module temporal_conv #(
    parameter int DATA_WIDTH = 16,
    parameter int COEF_WIDTH = 16,
    parameter int ACC_WIDTH  = 48, // Must be sufficient to hold KERNEL_SIZE * 2^(DATA+COEF)
    parameter int KERNEL_SIZE = 5,
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
    // Signal Definitions
    // -------------------------------------------------------------------------

    // Shift Register to store the last KERNEL_SIZE input samples.
    // shift_reg[0] will hold the most recent registered sample (x[n-1] effectively).
    logic signed [DATA_WIDTH-1:0] shift_reg [0:KERNEL_SIZE-1];

    // Internal Valid Pipeline
    logic valid_d;

    // Accumulator Combinational Signal
    logic signed [ACC_WIDTH-1:0] acc_comb;

    // -------------------------------------------------------------------------
    // Shift Register Logic
    // -------------------------------------------------------------------------
    // Updates when x_valid is high.
    // shift_reg[0] <= x_in
    // shift_reg[i] <= shift_reg[i-1]
    
    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < KERNEL_SIZE; i++) begin
                shift_reg[i] <= '0;
            end
        end else if (x_valid) begin
            // Shift in new sample at index 0 (matching COEFFS[0])
            // and shift existing samples down.
            shift_reg[0] <= x_in;
            for (int i = 1; i < KERNEL_SIZE; i++) begin
                shift_reg[i] <= shift_reg[i-1];
            end
        end
    end

    // -------------------------------------------------------------------------
    // Multiply-Accumulate (MAC) Logic
    // -------------------------------------------------------------------------
    // Fully combinational sum-of-products based on the current Shift Register state.
    // Since shift_reg updates on the clock edge, this logic computes based on
    // the values AVAILABLE in the register (i.e., from the previous cycle's load).
    
    always_comb begin
        acc_comb = '0;
        for (int i = 0; i < KERNEL_SIZE; i++) begin
            // Cast to accumulator width before addition to ensure no overflow during sum.
            // Product can be up to DATA_WIDTH + COEF_WIDTH bits.
            acc_comb = acc_comb + ( (ACC_WIDTH)'(shift_reg[i]) * (ACC_WIDTH)'(COEFFS[i]) );
        end
    end

    // -------------------------------------------------------------------------
    // Output Registration
    // -------------------------------------------------------------------------
    // Register the accumulator result to improve timing.
    // Also pipeline the valid signal.
    
    always_ff @(posedge clk) begin
        if (rst) begin
            y_out   <= '0;
            y_valid <= 1'b0;
            valid_d <= 1'b0;
        end else begin
            // Pipeline valid signal to match data path latency.
            // Data path: Input -> FF (shift_reg) -> Comb (MAC) -> FF (y_out)
            // x_valid should enable the shift_reg.
            // When x_valid is high, shift_reg captures new data.
            // The MAC logic produces the result for that data immediately (combinatorially from the NEW Q output? NO).
            // FF output changes AFTER clock edge.
            // So in cycle T, if shift_reg updates, shift_reg Q outputs change.
            // In Cycle T+1, acc_comb reflects the NEW shift_reg values.
            // y_out captures acc_comb at the end of T+1 (available T+2).
            
            // Let's trace carefully:
            // T0: x_valid=1. shift_reg updates at T0->T1 edge.
            // T1: shift_reg has new data. acc_comb is valid for this data. valid_d needs to be 1 here?
            //     To have y_out update at T1->T2 edge with this result, we need to flop it.
            //     So y_out gets correct value at T2.
            //     y_valid should be 1 at T2.
            
            // Therefore, we need to propagate x_valid through 2 registers?
            // Wait:
            // valid_d <= x_valid;  (At T1, valid_d becomes x_valid@T0)
            // y_valid <= valid_d;  (At T2, y_valid becomes valid_d@T1 which is x_valid@T0)
            // This gives 2 cycle latency.
            
            valid_d <= x_valid;
            y_valid <= valid_d;
            
            // Update output register.
            // We update y_out always, or only when valid? 
            // For a clean stream, updating always is predictable, valid qualifies it.
            // However, to save power, we could enable only if valid_d is high.
            // But if x_valid drops, valid_d drops next cycle. The "tail" should be handled?
            // If x_valid drops, we just stop shifting. The pipe assumes continuous valid or gaps.
            // If there's a gap, valid_d will be 0.
            if (valid_d) begin
                // Truncation/Slicing:
                // We extract the most significant DATA_WIDTH bits (MSBs) to preserve dynamic range.
                // This assumes the inputs and coefficients are scaled such that the useful information is in the upper bits.
                y_out <= acc_comb[ACC_WIDTH-1 -: DATA_WIDTH]; 
            end
        end
    end

endmodule