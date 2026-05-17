/**
 * Module: temporal_multihead_attention
 *
 * NOTE: This is a hardware-friendly *approximation* of multi-head attention,
 *       not the QKV/softmax operator from the paper. Each head computes an
 *       L1-norm "energy" over its channels, the input is modulated by that
 *       energy, and the heads are averaged at the output. Treat it as a
 *       channel-gating block.
 *
 * Pipeline (3 cycles):
 *   1) Energy = sum_c |x[h,c]|, then >> ATTN_SHIFT.
 *   2) Modulated[h,c] = x[h,c] * energy[h], rescaled by >> FRAC_BITS, saturated.
 *   3) y[c] = ( sum_h Modulated[h,c] ) / NUM_HEADS, saturated.
 *
 * Parameters:
 *   DATA_WIDTH - Width of input and output samples (default: 16)
 *   NUM_CH     - Total input channels (default: 16)
 *   NUM_HEADS  - Number of heads (must divide NUM_CH) (default: 4)
 *   FRAC_BITS  - Fractional bits used to rescale Modulated (default: DATA_WIDTH/2)
 *   ATTN_SHIFT - Right shift on the unsigned energy before modulation (default: 4)
 */

module temporal_multihead_attention #(
    parameter int DATA_WIDTH = 16,
    parameter int NUM_CH     = 16,
    parameter int NUM_HEADS  = 4,
    parameter int FRAC_BITS  = DATA_WIDTH/2,
    parameter int ATTN_SHIFT = 4
) (
    input  logic clk,
    input  logic rst,

    input  logic signed [DATA_WIDTH-1:0] x_in [0:NUM_CH-1],
    input  logic                         x_valid,

    output logic signed [DATA_WIDTH-1:0] y_out [0:(NUM_CH/NUM_HEADS)-1],
    output logic                         y_valid
);

    // -------------------------------------------------------------------------
    // Elaboration-time check
    // -------------------------------------------------------------------------
    generate
        if ((NUM_CH % NUM_HEADS) != 0) begin : gen_param_error
            $error("NUM_CH (%0d) must be divisible by NUM_HEADS (%0d).", NUM_CH, NUM_HEADS);
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Derived
    // -------------------------------------------------------------------------
    localparam int CH_PER_HEAD   = NUM_CH / NUM_HEADS;
    localparam int ENERGY_WIDTH  = DATA_WIDTH + $clog2(CH_PER_HEAD) + 1;
    localparam int PROD_WIDTH    = DATA_WIDTH + ENERGY_WIDTH;
    localparam int HEADS_LOG2    = (NUM_HEADS <= 1) ? 1 : $clog2(NUM_HEADS);
    localparam int AGG_WIDTH     = DATA_WIDTH + HEADS_LOG2;

    // Saturation bounds at DATA_WIDTH
    localparam logic signed [PROD_WIDTH-1:0] SAT_MAX_P =
        (PROD_WIDTH)'(((1 <<< (DATA_WIDTH-1)) - 1));
    localparam logic signed [PROD_WIDTH-1:0] SAT_MIN_P =
        -(PROD_WIDTH)'(1 <<< (DATA_WIDTH-1));
    localparam logic signed [AGG_WIDTH:0]    SAT_MAX_A =
        (AGG_WIDTH+1)'(((1 <<< (DATA_WIDTH-1)) - 1));
    localparam logic signed [AGG_WIDTH:0]    SAT_MIN_A =
        -(AGG_WIDTH+1)'(1 <<< (DATA_WIDTH-1));

    // -------------------------------------------------------------------------
    // Pipeline registers
    // -------------------------------------------------------------------------
    logic [ENERGY_WIDTH-1:0]       head_energy_reg  [0:NUM_HEADS-1];
    logic signed [DATA_WIDTH-1:0]  x_d1_reg         [0:NUM_CH-1];
    logic                          valid_d1_reg;

    logic signed [DATA_WIDTH-1:0]  head_modulated_reg [0:NUM_HEADS-1][0:CH_PER_HEAD-1];
    logic                          valid_d2_reg;

    // -------------------------------------------------------------------------
    // Stage 1: L1-norm energy
    // -------------------------------------------------------------------------
    logic [ENERGY_WIDTH-1:0] head_energy_comb [0:NUM_HEADS-1];
    logic [ENERGY_WIDTH-1:0] energy_accum     [0:NUM_HEADS-1];

    always_comb begin
        for (int h = 0; h < NUM_HEADS; h++) begin
            energy_accum[h] = '0;
            for (int c = 0; c < CH_PER_HEAD; c++) begin
                logic signed [DATA_WIDTH-1:0] v;
                v = x_in[h*CH_PER_HEAD + c];
                energy_accum[h] = energy_accum[h] +
                    ((v < 0) ? (ENERGY_WIDTH)'(-v) : (ENERGY_WIDTH)'(v));
            end
            head_energy_comb[h] = energy_accum[h] >> ATTN_SHIFT;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int h = 0; h < NUM_HEADS; h++) head_energy_reg[h] <= '0;
            for (int i = 0; i < NUM_CH;   i++) x_d1_reg[i]        <= '0;
            valid_d1_reg <= 1'b0;
        end else begin
            valid_d1_reg <= x_valid;
            if (x_valid) begin
                head_energy_reg <= head_energy_comb;
                x_d1_reg        <= x_in;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Stage 2: Modulate (x * energy), rescale by >> FRAC_BITS, saturate
    // -------------------------------------------------------------------------
    logic signed [PROD_WIDTH-1:0]  prod_comb    [0:NUM_HEADS-1][0:CH_PER_HEAD-1];
    logic signed [PROD_WIDTH-1:0]  prod_shifted [0:NUM_HEADS-1][0:CH_PER_HEAD-1];
    logic signed [DATA_WIDTH-1:0]  prod_sat     [0:NUM_HEADS-1][0:CH_PER_HEAD-1];

    always_comb begin
        for (int h = 0; h < NUM_HEADS; h++) begin
            for (int c = 0; c < CH_PER_HEAD; c++) begin
                // signed_data * unsigned_energy → signed product
                prod_comb[h][c] = $signed(x_d1_reg[h*CH_PER_HEAD + c])
                                  * $signed({1'b0, head_energy_reg[h]});
                prod_shifted[h][c] = prod_comb[h][c] >>> FRAC_BITS;
                if (prod_shifted[h][c] > SAT_MAX_P)
                    prod_sat[h][c] = SAT_MAX_P[DATA_WIDTH-1:0];
                else if (prod_shifted[h][c] < SAT_MIN_P)
                    prod_sat[h][c] = SAT_MIN_P[DATA_WIDTH-1:0];
                else
                    prod_sat[h][c] = prod_shifted[h][c][DATA_WIDTH-1:0];
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int h = 0; h < NUM_HEADS; h++)
                for (int c = 0; c < CH_PER_HEAD; c++)
                    head_modulated_reg[h][c] <= '0;
            valid_d2_reg <= 1'b0;
        end else begin
            valid_d2_reg <= valid_d1_reg;
            if (valid_d1_reg) begin
                for (int h = 0; h < NUM_HEADS; h++)
                    for (int c = 0; c < CH_PER_HEAD; c++)
                        head_modulated_reg[h][c] <= prod_sat[h][c];
            end
        end
    end

    // -------------------------------------------------------------------------
    // Stage 3: Aggregate (average across heads) + saturate
    // -------------------------------------------------------------------------
    logic signed [AGG_WIDTH:0]    agg_comb     [0:CH_PER_HEAD-1];
    logic signed [AGG_WIDTH:0]    agg_shifted  [0:CH_PER_HEAD-1];

    always_comb begin
        for (int c = 0; c < CH_PER_HEAD; c++) begin
            agg_comb[c] = '0;
            for (int h = 0; h < NUM_HEADS; h++)
                agg_comb[c] = agg_comb[c] + head_modulated_reg[h][c];
            agg_shifted[c] = agg_comb[c] >>> HEADS_LOG2;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int c = 0; c < CH_PER_HEAD; c++) y_out[c] <= '0;
            y_valid <= 1'b0;
        end else begin
            y_valid <= valid_d2_reg;
            if (valid_d2_reg) begin
                for (int c = 0; c < CH_PER_HEAD; c++) begin
                    if (agg_shifted[c] > SAT_MAX_A)
                        y_out[c] <= SAT_MAX_A[DATA_WIDTH-1:0];
                    else if (agg_shifted[c] < SAT_MIN_A)
                        y_out[c] <= SAT_MIN_A[DATA_WIDTH-1:0];
                    else
                        y_out[c] <= agg_shifted[c][DATA_WIDTH-1:0];
                end
            end
        end
    end

endmodule
