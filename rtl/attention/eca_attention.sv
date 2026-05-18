// =============================================================================
// eca_attention.sv  —  Efficient Channel Attention (Wang et al. 2020)
//
// Implements the ECA operator used by DB-ATCNet:
//
//   x ∈ R[N, T, C]     (T = number of time steps in the feature map)
//   g[c] = mean_t x[n, t, c]                        // global average pool
//   z[c] = sigmoid( conv1d(g, kernel_size=ECA_K, filters=1) [c] )
//   y[n, t, c] = x[n, t, c] * z[c]
//
// Compared to SE (squeeze-excite), ECA replaces the two dense MLP layers
// with a single 1D convolution of small kernel (typically 3 or 5). It has
// no per-channel bottleneck and no learned bias — much smaller on hardware.
//
// Per the original Keras code (kernel_size = round_odd((log2(C)+1)/2)):
//   C = 16 -> ECA_K = 3
//   C = 32 -> ECA_K = 3
// Larger C grows ECA_K slowly. Default here is 3.
//
// Pipeline:
//   Stage A: Streaming GAP — accumulates T samples per channel, then divides.
//   Stage B: 1D conv of length ECA_K over the per-channel vector (k taps,
//            1-in 1-out, no bias).
//   Stage C: hard-sigmoid → per-channel scale factor.
//   Stage D: Multiply each new x[n,t,c] by scale[c] (held for one frame).
//
// This module performs Stages A-C and exposes scale_out[]. The downstream
// caller does Stage D (a per-channel multiply) on the saved/streamed feature
// map. Two reasons: (i) the feature map is large and we don't want to buffer
// it here; (ii) the caller already has the multiply unit for the next layer.
//
// Parameters:
//   DATA_WIDTH  signed activation width  (default 16)
//   COEF_WIDTH  signed weight   width    (default 16)
//   ACC_WIDTH   accumulator width        (default 32)
//   FRAC_BITS   fixed-point fractional bits (default 8 -> Q8.8)
//   NUM_CH      number of channels       (default 16)
//   TIME_STEPS  number of time steps the GAP averages over
//   ECA_K       1D conv kernel length    (default 3, must be odd)
//   W_ECA       1D conv weights, length ECA_K, signed Q-format
// =============================================================================

`timescale 1ns / 1ps

module eca_attention #(
    parameter int DATA_WIDTH = 16,
    parameter int COEF_WIDTH = 16,
    parameter int ACC_WIDTH  = 32,
    parameter int FRAC_BITS  = 8,
    parameter int NUM_CH     = 16,
    parameter int TIME_STEPS = 640,
    parameter int ECA_K      = 3,
    parameter logic signed [COEF_WIDTH-1:0] W_ECA [0:ECA_K-1] = '{default: 0}
) (
    input  logic clk,
    input  logic rst,

    // Streaming feature map: one (channel-vector) per "time-step".
    // x_valid pulses TIME_STEPS times per frame.
    input  logic signed [DATA_WIDTH-1:0] x_in [0:NUM_CH-1],
    input  logic                         x_valid,
    input  logic                         frame_last,   // pulse on the last time step

    // Per-channel attention scale (Q0.FRAC_BITS, [0,1])
    output logic signed [DATA_WIDTH-1:0] scale_out [0:NUM_CH-1],
    output logic                         scale_valid
);

    // ---------------------------------------------------------------------
    // Q-format helpers
    // ---------------------------------------------------------------------
    localparam logic signed [ACC_WIDTH-1:0] SAT_HI =
        (ACC_WIDTH)'(((1 <<< (DATA_WIDTH-1)) - 1));
    localparam logic signed [ACC_WIDTH-1:0] SAT_LO =
        -(ACC_WIDTH)'(1 <<< (DATA_WIDTH-1));

    function automatic logic signed [DATA_WIDTH-1:0] sat_shr(
        input logic signed [ACC_WIDTH-1:0] v, input int shift);
        logic signed [ACC_WIDTH-1:0] s;
        begin
            s = v >>> shift;
            if (s > SAT_HI)      sat_shr = SAT_HI[DATA_WIDTH-1:0];
            else if (s < SAT_LO) sat_shr = SAT_LO[DATA_WIDTH-1:0];
            else                 sat_shr = s[DATA_WIDTH-1:0];
        end
    endfunction

    // hard_sigmoid(x) = clamp(x/4 + 0.5, 0, 1) in Q.FRAC_BITS
    function automatic logic signed [DATA_WIDTH-1:0] hard_sigmoid(
        input logic signed [DATA_WIDTH-1:0] v);
        logic signed [DATA_WIDTH:0] tmp;
        logic signed [DATA_WIDTH:0] half;
        logic signed [DATA_WIDTH:0] one;
        begin
            half = (DATA_WIDTH+1)'(1 <<< (FRAC_BITS-1));
            one  = (DATA_WIDTH+1)'(1 <<< (FRAC_BITS));
            tmp  = (v >>> 2) + half;
            if (tmp < 0)        hard_sigmoid = '0;
            else if (tmp > one) hard_sigmoid = one[DATA_WIDTH-1:0];
            else                hard_sigmoid = tmp[DATA_WIDTH-1:0];
        end
    endfunction

    // log2(TIME_STEPS) — the right-shift to perform the average. We assume
    // TIME_STEPS is a power of two for clean hardware. If not, replace with
    // a multiply-by-reciprocal in Q-format.
    localparam int T_LOG2 = $clog2(TIME_STEPS);

    // ---------------------------------------------------------------------
    // Stage A: Global Average Pool — per-channel running sum
    // ---------------------------------------------------------------------
    logic signed [ACC_WIDTH-1:0] sum_acc [0:NUM_CH-1];
    logic signed [DATA_WIDTH-1:0] g_reg   [0:NUM_CH-1];   // pooled vector
    logic                         g_valid;

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int c = 0; c < NUM_CH; c++) sum_acc[c] <= '0;
            for (int c = 0; c < NUM_CH; c++) g_reg[c]   <= '0;
            g_valid <= 1'b0;
        end else begin
            g_valid <= 1'b0;
            if (x_valid) begin
                for (int c = 0; c < NUM_CH; c++)
                    sum_acc[c] <= sum_acc[c] + $signed(x_in[c]);
                if (frame_last) begin
                    for (int c = 0; c < NUM_CH; c++)
                        g_reg[c] <= sat_shr(sum_acc[c] + $signed(x_in[c]), T_LOG2);
                    for (int c = 0; c < NUM_CH; c++) sum_acc[c] <= '0;
                    g_valid <= 1'b1;
                end
            end
        end
    end

    // ---------------------------------------------------------------------
    // Stage B: 1D conv across the channel dimension (length ECA_K).
    // Padding is 'same' with kernel centered: index c reads g[c-K/2..c+K/2].
    // ---------------------------------------------------------------------
    localparam int HALF_K = ECA_K / 2;

    logic signed [ACC_WIDTH-1:0] eca_acc [0:NUM_CH-1];
    logic signed [DATA_WIDTH-1:0] s_pre  [0:NUM_CH-1];
    logic                         s_pre_valid;

    always_comb begin
        for (int c = 0; c < NUM_CH; c++) begin
            eca_acc[c] = '0;
            for (int k = 0; k < ECA_K; k++) begin
                int idx;
                idx = c + k - HALF_K;
                if (idx >= 0 && idx < NUM_CH)
                    eca_acc[c] = eca_acc[c] + $signed(g_reg[idx]) * $signed(W_ECA[k]);
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int c = 0; c < NUM_CH; c++) s_pre[c] <= '0;
            s_pre_valid <= 1'b0;
        end else begin
            s_pre_valid <= g_valid;
            if (g_valid) begin
                for (int c = 0; c < NUM_CH; c++)
                    s_pre[c] <= sat_shr(eca_acc[c], FRAC_BITS);
            end
        end
    end

    // ---------------------------------------------------------------------
    // Stage C: hard_sigmoid -> scale_out
    // ---------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            for (int c = 0; c < NUM_CH; c++) scale_out[c] <= '0;
            scale_valid <= 1'b0;
        end else begin
            scale_valid <= s_pre_valid;
            if (s_pre_valid) begin
                for (int c = 0; c < NUM_CH; c++)
                    scale_out[c] <= hard_sigmoid(s_pre[c]);
            end
        end
    end

endmodule
