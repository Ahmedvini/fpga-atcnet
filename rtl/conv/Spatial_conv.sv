module spatial_conv_serial_stream #(
    parameter int C_IN   = 8,
    parameter int C_OUT  = 8,
    parameter int DATA_W = 16,   // Q8.8
    parameter int COEF_W = 16,   // Q8.8
    parameter int ACC_W  = 48,
    parameter int SHIFT  = 8,    // Q8.8 scaling
    parameter logic signed [COEF_W-1:0] W [0:C_OUT-1][0:C_IN-1] = '{default:'{default:0}}
)(
    input  logic clk,
    input  logic rst,                 // active-high reset

    // Stream input: channel-interleaved samples
    input  logic                     x_valid,
    input  logic signed [DATA_W-1:0]  x_in,

    // Stream output: feature-interleaved outputs
    output logic                     y_valid,
    output logic signed [DATA_W-1:0]  y_out
);

    // Counters
    logic [$clog2(C_IN)-1:0]  chan_idx;
    logic [$clog2(C_OUT)-1:0] feat_idx;

    // Accumulator for current output feature
    logic signed [ACC_W-1:0] acc;

    // Product for current (feat_idx, chan_idx)
    logic signed [ACC_W-1:0] prod;

    assign prod = (ACC_W)'($signed(x_in)) * (ACC_W)'($signed(W[feat_idx][chan_idx]));

    always_ff @(posedge clk) begin
        if (rst) begin
            chan_idx <= '0;
            feat_idx <= '0;
            acc      <= '0;
            y_valid  <= 1'b0;
            y_out    <= '0;
        end else begin
            y_valid <= 1'b0; // default

            if (x_valid) begin
                // accumulate this channel contribution
                if (chan_idx == '0)
                    acc <= prod;         // start sum for this feature
                else
                    acc <= acc + prod;   // continue sum

                // advance channel counter
                if (chan_idx == C_IN-1) begin
                    // finished dot-product for current feature -> output it
                    y_out   <= ( (chan_idx == '0) ? prod : (acc + prod) ) >>> SHIFT;
                    y_valid <= 1'b1;

                    chan_idx <= '0;

                    // move to next feature
                    if (feat_idx == C_OUT-1)
                        feat_idx <= '0;     // next time-step starts (assumed stream continues)
                    else
                        feat_idx <= feat_idx + 1'b1;
                end else begin
                    chan_idx <= chan_idx + 1'b1;
                end
            end
        end
    end

endmodule
