/**
 * Module: channel_scale
 *
 * Description:
 *   Per-channel signed fixed-point scaling: y[i] = x[i] * SCALE[i].
 *   Inputs and SCALE are Q(I).(FRAC_BITS); the product is Q(2I).(2*FRAC_BITS)
 *   and is rescaled to DATA_WIDTH via arithmetic right-shift by FRAC_BITS and
 *   symmetric saturation.
 *
 * Latency:
 *   1 cycle from x_valid to y_valid.
 *
 * Parameters:
 *   DATA_WIDTH - Width of input and output samples (default: 16)
 *   COEF_WIDTH - Width of scaling coefficients (default: 16)
 *   NUM_CH     - Number of channels (default: 4)
 *   FRAC_BITS  - Fractional bits in SCALE (default: COEF_WIDTH/2)
 *   SCALE      - Per-channel signed scale factors.
 */

module channel_scale #(
    parameter int DATA_WIDTH = 16,
    parameter int COEF_WIDTH = 16,
    parameter int NUM_CH     = 4,
    parameter int FRAC_BITS  = COEF_WIDTH/2,
    parameter logic signed [COEF_WIDTH-1:0] SCALE [0:NUM_CH-1] = '{default: 0}
) (
    input  logic clk,
    input  logic rst,

    input  logic signed [DATA_WIDTH-1:0] x_in [0:NUM_CH-1],
    input  logic                         x_valid,

    output logic signed [DATA_WIDTH-1:0] y_out [0:NUM_CH-1],
    output logic                         y_valid
);

    localparam int PROD_WIDTH = DATA_WIDTH + COEF_WIDTH;

    logic signed [PROD_WIDTH-1:0] product   [0:NUM_CH-1];
    logic signed [PROD_WIDTH-1:0] shifted   [0:NUM_CH-1];
    logic signed [DATA_WIDTH-1:0] saturated [0:NUM_CH-1];

    localparam logic signed [PROD_WIDTH-1:0] SAT_MAX =
        (PROD_WIDTH)'(((1 <<< (DATA_WIDTH-1)) - 1));
    localparam logic signed [PROD_WIDTH-1:0] SAT_MIN =
        -(PROD_WIDTH)'(1 <<< (DATA_WIDTH-1));

    always_comb begin
        for (int i = 0; i < NUM_CH; i++) begin
            product[i] = $signed(x_in[i]) * $signed(SCALE[i]);
            shifted[i] = product[i] >>> FRAC_BITS;
            if (shifted[i] > SAT_MAX)      saturated[i] = SAT_MAX[DATA_WIDTH-1:0];
            else if (shifted[i] < SAT_MIN) saturated[i] = SAT_MIN[DATA_WIDTH-1:0];
            else                           saturated[i] = shifted[i][DATA_WIDTH-1:0];
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < NUM_CH; i++) y_out[i] <= '0;
            y_valid <= 1'b0;
        end else begin
            y_valid <= x_valid;
            if (x_valid) begin
                for (int i = 0; i < NUM_CH; i++) y_out[i] <= saturated[i];
            end
        end
    end

endmodule
