/**
 * Module: spatial_conv
 *
 * Description:
 *   Serial channel-interleaved 1x1 spatial convolution.
 *   For each output feature f in [0, C_OUT), accumulates a dot-product over
 *   the C_IN input channels: y[f] = sum_c ( W[f][c] * x[c] ).
 *
 *   Inputs arrive channel-interleaved (one x per cycle when x_valid is high).
 *   One y_out is emitted every C_IN cycles (on the last channel of each
 *   feature), with y_valid pulsed for one cycle.
 *
 *   Numerical model: Q(I).(FRAC_BITS) for both x and W. After the dot product
 *   the accumulator is arithmetic-right-shifted by FRAC_BITS and saturated to
 *   DATA_W bits.
 */

module spatial_conv #(
    parameter int C_IN      = 8,
    parameter int C_OUT     = 8,
    parameter int DATA_W    = 16,
    parameter int COEF_W    = 16,
    parameter int ACC_W     = 48,
    parameter int FRAC_BITS = COEF_W/2,
    parameter logic signed [COEF_W-1:0] W [0:C_OUT-1][0:C_IN-1] = '{default: 0}
)(
    input  logic clk,
    input  logic rst,

    input  logic                     x_valid,
    input  logic signed [DATA_W-1:0] x_in,

    output logic                     y_valid,
    output logic signed [DATA_W-1:0] y_out
);

    localparam int CH_IDX_W   = (C_IN  <= 1) ? 1 : $clog2(C_IN);
    localparam int FEAT_IDX_W = (C_OUT <= 1) ? 1 : $clog2(C_OUT);

    logic [CH_IDX_W-1:0]   chan_idx;
    logic [FEAT_IDX_W-1:0] feat_idx;

    logic signed [ACC_W-1:0] acc;
    logic signed [ACC_W-1:0] prod;
    logic signed [ACC_W-1:0] dot_full;
    logic signed [ACC_W-1:0] dot_shift;

    assign prod     = $signed(x_in) * $signed(W[feat_idx][chan_idx]);
    assign dot_full = (chan_idx == 0) ? prod : (acc + prod);
    assign dot_shift = dot_full >>> FRAC_BITS;

    localparam logic signed [ACC_W-1:0] SAT_MAX =
        (ACC_W)'(((1 <<< (DATA_W-1)) - 1));
    localparam logic signed [ACC_W-1:0] SAT_MIN =
        -(ACC_W)'(1 <<< (DATA_W-1));

    always_ff @(posedge clk) begin
        if (rst) begin
            chan_idx <= '0;
            feat_idx <= '0;
            acc      <= '0;
            y_valid  <= 1'b0;
            y_out    <= '0;
        end else begin
            y_valid <= 1'b0;
            if (x_valid) begin
                // Accumulate this channel contribution.
                acc <= dot_full;

                if (chan_idx == C_IN-1) begin
                    // Finished dot-product for this output feature.
                    if (dot_shift > SAT_MAX)      y_out <= SAT_MAX[DATA_W-1:0];
                    else if (dot_shift < SAT_MIN) y_out <= SAT_MIN[DATA_W-1:0];
                    else                          y_out <= dot_shift[DATA_W-1:0];
                    y_valid  <= 1'b1;

                    chan_idx <= '0;
                    feat_idx <= (feat_idx == C_OUT-1) ? '0 : feat_idx + 1'b1;
                end else begin
                    chan_idx <= chan_idx + 1'b1;
                end
            end
        end
    end

endmodule
