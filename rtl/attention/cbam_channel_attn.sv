// =============================================================================
// cbam_channel_attn.sv  —  ImpCBAM channel-attention block (one sliding window).
//
// Math (matches scripts/q88_layer17_chan.py bit-exactly):
//
//     in_stream  : NUM_CH-wide vector per cycle, T_WIN of them per window.
//     avg_gap[c] = sat( (sum_t in[t,c] * INV_N) >>> 24 )
//     max_gap[c] = max_t in[t,c]
//     mlp(x)[o]  = Dense₂( ReLU( Dense₁(x) ) )                  // shared between paths
//     gate[c]    = sigmoid_LUT( sat( mlp(avg_gap)[c] + mlp(max_gap)[c] ) )
//     out[t,c]   = sat( in[t,c] * gate[c] >>> 8 )
//
// Dense₁ kernel: (D_RED × NUM_CH) stored output-major, biases length D_RED.
// Dense₂ kernel: (NUM_CH × D_RED) stored output-major, biases length NUM_CH.
//
// Pipeline (single window):
//   Phase 1: stream T_WIN vectors → accumulate avg_sum / running max.
//   Phase 2: on `frame_last` pulse: build avg_gap & max_gap; run shared MLP
//            on both; sigmoid; latch gate.
//   Phase 3: re-stream the T_WIN vectors → multiply by latched gate.
//
// The TB is responsible for streaming the same window twice (phase 1 then
// phase 3). The DUT is purely combinational+register; it does not buffer
// the input itself.
//
// Latency from `gate_valid` is 1 cycle on each x_valid in Phase 3.
//
// Resources (fully-parallel):
//   Dense₁: D_RED * NUM_CH = 128 multiplies (combinational)
//   Dense₂: NUM_CH * D_RED = 128 multiplies (combinational)
//   gate_apply: NUM_CH multiplies (combinational)
// =============================================================================

`timescale 1ns / 1ps

module cbam_channel_attn #(
    parameter int    DATA_WIDTH    = 16,
    parameter int    COEF_WIDTH    = 16,
    parameter int    ACC_WIDTH     = 32,
    parameter int    FRAC_BITS     = 8,
    parameter int    NUM_CH        = 32,
    parameter int    T_WIN         = 6,
    parameter int    D_RED         = 4,
    parameter int    INV_N         = 2796203,    // round(2^24 / 6)
    parameter int    INV_N_SHIFT   = 24,
    parameter int    INV_N_WIDTH   = 24,
    parameter int    LUT_N         = 1024,
    parameter int    LUT_RANGE_Q   = 1024,
    parameter int    LUT_SHIFT     = 1,
    parameter string D1_W_FILE     = "",
    parameter string D1_B_FILE     = "",
    parameter string D2_W_FILE     = "",
    parameter string D2_B_FILE     = "",
    parameter string LUT_FILE      = ""
) (
    input  logic                              clk,
    input  logic                              rst,

    // Streaming feature map (window of T_WIN vectors).
    input  logic signed [DATA_WIDTH-1:0]      x_in [0:NUM_CH-1],
    input  logic                              x_valid,
    input  logic                              frame_last,   // 1 on the T_WIN-th input

    output logic signed [DATA_WIDTH-1:0]      gate_out [0:NUM_CH-1],
    output logic                              gate_valid,   // pulses 1 cycle when gate updates

    // Phase 3: apply gate to a re-streamed input.
    input  logic signed [DATA_WIDTH-1:0]      apply_x_in [0:NUM_CH-1],
    input  logic                              apply_valid,
    output logic signed [DATA_WIDTH-1:0]      y_out [0:NUM_CH-1],
    output logic                              y_valid
);

    // -------------------------------------------------------------------------
    // Weight memories ($readmemh at elaboration)
    // -------------------------------------------------------------------------
    // Dense₁: output-major (o, i) flat; index = o*NUM_CH + i.
    logic signed [COEF_WIDTH-1:0] D1_W [0:D_RED * NUM_CH - 1];
    logic signed [DATA_WIDTH-1:0] D1_B [0:D_RED - 1];
    // Dense₂: output-major (o, i) flat; index = o*D_RED + i.
    logic signed [COEF_WIDTH-1:0] D2_W [0:NUM_CH * D_RED - 1];
    logic signed [DATA_WIDTH-1:0] D2_B [0:NUM_CH - 1];
    logic signed [DATA_WIDTH-1:0] LUT  [0:LUT_N - 1];

    initial begin
        if (D1_W_FILE != "") $readmemh(D1_W_FILE, D1_W);
        if (D1_B_FILE != "") $readmemh(D1_B_FILE, D1_B);
        if (D2_W_FILE != "") $readmemh(D2_W_FILE, D2_W);
        if (D2_B_FILE != "") $readmemh(D2_B_FILE, D2_B);
        if (LUT_FILE  != "") $readmemh(LUT_FILE,  LUT);
    end

    localparam logic signed [ACC_WIDTH-1:0] SAT_HI =
        (ACC_WIDTH)'((1 <<< (DATA_WIDTH-1)) - 1);
    localparam logic signed [ACC_WIDTH-1:0] SAT_LO =
        -(ACC_WIDTH)'(1 <<< (DATA_WIDTH-1));

    // -------------------------------------------------------------------------
    // Phase 1 accumulators (avg & max over T_WIN steps)
    // -------------------------------------------------------------------------
    logic signed [ACC_WIDTH-1:0]  avg_acc  [0:NUM_CH-1];
    logic signed [DATA_WIDTH-1:0] max_acc  [0:NUM_CH-1];

    localparam logic signed [DATA_WIDTH-1:0] DATA_MIN = {1'b1, {(DATA_WIDTH-1){1'b0}}};

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int c = 0; c < NUM_CH; c++) begin
                avg_acc[c] <= '0;
                max_acc[c] <= DATA_MIN;
            end
        end else if (x_valid && frame_last) begin
            for (int c = 0; c < NUM_CH; c++) begin
                avg_acc[c] <= $signed(x_in[c]);
                max_acc[c] <= $signed(x_in[c]);
            end
        end else if (x_valid) begin
            for (int c = 0; c < NUM_CH; c++) begin
                avg_acc[c] <= avg_acc[c] + $signed(x_in[c]);
                if ($signed(x_in[c]) > max_acc[c]) max_acc[c] <= $signed(x_in[c]);
            end
        end
    end

    // Combinational "final" view of accumulators at frame_last.
    logic signed [ACC_WIDTH-1:0]  avg_final [0:NUM_CH-1];
    logic signed [DATA_WIDTH-1:0] max_final [0:NUM_CH-1];
    always_comb begin
        for (int c = 0; c < NUM_CH; c++) begin
            avg_final[c] = avg_acc[c] + $signed(x_in[c]);
            max_final[c] = ($signed(x_in[c]) > max_acc[c]) ? $signed(x_in[c]) : max_acc[c];
        end
    end

    // -------------------------------------------------------------------------
    // Phase 2: avg GAP via reciprocal multiply (saturated)
    // -------------------------------------------------------------------------
    localparam int MUL_WIDTH_AVG = ACC_WIDTH + INV_N_WIDTH;
    logic signed [MUL_WIDTH_AVG-1:0] avg_prod    [0:NUM_CH-1];
    logic signed [MUL_WIDTH_AVG-1:0] avg_shifted [0:NUM_CH-1];
    logic signed [DATA_WIDTH-1:0]    avg_gap     [0:NUM_CH-1];
    logic signed [DATA_WIDTH-1:0]    max_gap     [0:NUM_CH-1];

    always_comb begin
        for (int c = 0; c < NUM_CH; c++) begin
            avg_prod[c]    = avg_final[c] * $signed({1'b0, INV_N_WIDTH'(INV_N)});
            avg_shifted[c] = avg_prod[c] >>> INV_N_SHIFT;
            if      (avg_shifted[c] >  SAT_HI) avg_gap[c] = SAT_HI[DATA_WIDTH-1:0];
            else if (avg_shifted[c] <  SAT_LO) avg_gap[c] = SAT_LO[DATA_WIDTH-1:0];
            else                               avg_gap[c] = avg_shifted[c][DATA_WIDTH-1:0];
            max_gap[c] = max_final[c];
        end
    end

    // -------------------------------------------------------------------------
    // Dense₁: gap (32) -> hidden (4) with ReLU. Two parallel copies, one for
    // avg path and one for max path.
    // -------------------------------------------------------------------------
    localparam int D1_ACC_WIDTH = 40;   // 16-bit * 16-bit * 32 ≤ 32+log2(32)+1 = 38 → 40 safe

    function automatic logic signed [DATA_WIDTH-1:0] dense_step (
        input  logic signed [DATA_WIDTH-1:0]      x_vec  [0:31],
        input  int                                in_cnt,
        input  int                                out_idx,
        input  logic signed [COEF_WIDTH-1:0]      W_flat [],
        input  logic signed [DATA_WIDTH-1:0]      bias
    );
        logic signed [D1_ACC_WIDTH-1:0] acc;
        logic signed [D1_ACC_WIDTH-1:0] shifted;
        acc = '0;
        for (int i = 0; i < in_cnt; i++)
            acc = acc + $signed(x_vec[i]) * $signed(W_flat[out_idx * in_cnt + i]);
        shifted = (acc >>> FRAC_BITS) + bias;
        if      (shifted > SAT_HI) return SAT_HI[DATA_WIDTH-1:0];
        else if (shifted < SAT_LO) return SAT_LO[DATA_WIDTH-1:0];
        else                       return shifted[DATA_WIDTH-1:0];
    endfunction

    logic signed [D1_ACC_WIDTH-1:0] d1_acc_avg [0:D_RED-1];
    logic signed [D1_ACC_WIDTH-1:0] d1_acc_max [0:D_RED-1];
    logic signed [D1_ACC_WIDTH-1:0] d1_sh_avg  [0:D_RED-1];
    logic signed [D1_ACC_WIDTH-1:0] d1_sh_max  [0:D_RED-1];
    logic signed [DATA_WIDTH-1:0]   d1_avg_h   [0:D_RED-1];
    logic signed [DATA_WIDTH-1:0]   d1_max_h   [0:D_RED-1];

    always_comb begin
        for (int o = 0; o < D_RED; o++) begin
            d1_acc_avg[o] = '0;
            d1_acc_max[o] = '0;
            for (int i = 0; i < NUM_CH; i++) begin
                d1_acc_avg[o] = d1_acc_avg[o] + $signed(avg_gap[i]) * $signed(D1_W[o * NUM_CH + i]);
                d1_acc_max[o] = d1_acc_max[o] + $signed(max_gap[i]) * $signed(D1_W[o * NUM_CH + i]);
            end
            d1_sh_avg[o] = (d1_acc_avg[o] >>> FRAC_BITS)
                         + $signed({{(D1_ACC_WIDTH-DATA_WIDTH){D1_B[o][DATA_WIDTH-1]}}, D1_B[o]});
            d1_sh_max[o] = (d1_acc_max[o] >>> FRAC_BITS)
                         + $signed({{(D1_ACC_WIDTH-DATA_WIDTH){D1_B[o][DATA_WIDTH-1]}}, D1_B[o]});
            // Saturate to Q8.8 then ReLU
            if      (d1_sh_avg[o] >  SAT_HI) d1_avg_h[o] = SAT_HI[DATA_WIDTH-1:0];
            else if (d1_sh_avg[o] <  SAT_LO) d1_avg_h[o] = '0;          // negative → ReLU 0
            else if (d1_sh_avg[o] <  0)      d1_avg_h[o] = '0;
            else                             d1_avg_h[o] = d1_sh_avg[o][DATA_WIDTH-1:0];
            if      (d1_sh_max[o] >  SAT_HI) d1_max_h[o] = SAT_HI[DATA_WIDTH-1:0];
            else if (d1_sh_max[o] <  SAT_LO) d1_max_h[o] = '0;
            else if (d1_sh_max[o] <  0)      d1_max_h[o] = '0;
            else                             d1_max_h[o] = d1_sh_max[o][DATA_WIDTH-1:0];
        end
    end

    // -------------------------------------------------------------------------
    // Dense₂: hidden (4) -> output (32). Combine paths after.
    // -------------------------------------------------------------------------
    logic signed [D1_ACC_WIDTH-1:0] d2_acc_avg [0:NUM_CH-1];
    logic signed [D1_ACC_WIDTH-1:0] d2_acc_max [0:NUM_CH-1];
    logic signed [D1_ACC_WIDTH-1:0] d2_sh_avg  [0:NUM_CH-1];
    logic signed [D1_ACC_WIDTH-1:0] d2_sh_max  [0:NUM_CH-1];
    logic signed [DATA_WIDTH-1:0]   d2_avg_out [0:NUM_CH-1];
    logic signed [DATA_WIDTH-1:0]   d2_max_out [0:NUM_CH-1];

    always_comb begin
        for (int o = 0; o < NUM_CH; o++) begin
            d2_acc_avg[o] = '0;
            d2_acc_max[o] = '0;
            for (int i = 0; i < D_RED; i++) begin
                d2_acc_avg[o] = d2_acc_avg[o] + $signed(d1_avg_h[i]) * $signed(D2_W[o * D_RED + i]);
                d2_acc_max[o] = d2_acc_max[o] + $signed(d1_max_h[i]) * $signed(D2_W[o * D_RED + i]);
            end
            d2_sh_avg[o] = (d2_acc_avg[o] >>> FRAC_BITS)
                         + $signed({{(D1_ACC_WIDTH-DATA_WIDTH){D2_B[o][DATA_WIDTH-1]}}, D2_B[o]});
            d2_sh_max[o] = (d2_acc_max[o] >>> FRAC_BITS)
                         + $signed({{(D1_ACC_WIDTH-DATA_WIDTH){D2_B[o][DATA_WIDTH-1]}}, D2_B[o]});
            if      (d2_sh_avg[o] >  SAT_HI) d2_avg_out[o] = SAT_HI[DATA_WIDTH-1:0];
            else if (d2_sh_avg[o] <  SAT_LO) d2_avg_out[o] = SAT_LO[DATA_WIDTH-1:0];
            else                             d2_avg_out[o] = d2_sh_avg[o][DATA_WIDTH-1:0];
            if      (d2_sh_max[o] >  SAT_HI) d2_max_out[o] = SAT_HI[DATA_WIDTH-1:0];
            else if (d2_sh_max[o] <  SAT_LO) d2_max_out[o] = SAT_LO[DATA_WIDTH-1:0];
            else                             d2_max_out[o] = d2_sh_max[o][DATA_WIDTH-1:0];
        end
    end

    // -------------------------------------------------------------------------
    // Add(avg, max) → saturate → sigmoid via LUT → gate (registered)
    // -------------------------------------------------------------------------
    localparam int                                ADDR_W       = $clog2(LUT_N);
    localparam logic signed [DATA_WIDTH-1:0]      LUT_CLIP_HI  = LUT_RANGE_Q - 1;
    localparam logic signed [DATA_WIDTH-1:0]      LUT_CLIP_LO  = -LUT_RANGE_Q;

    logic signed [DATA_WIDTH-1:0] sig_in   [0:NUM_CH-1];
    logic signed [DATA_WIDTH-1:0] clipped  [0:NUM_CH-1];
    logic        [ADDR_W-1:0]     addr     [0:NUM_CH-1];

    localparam logic signed [DATA_WIDTH:0] S17_HI =  (1 <<< (DATA_WIDTH-1)) - 1;
    localparam logic signed [DATA_WIDTH:0] S17_LO = -(1 <<< (DATA_WIDTH-1));

    always_comb begin
        for (int c = 0; c < NUM_CH; c++) begin
            logic signed [DATA_WIDTH:0] s;
            s = {d2_avg_out[c][DATA_WIDTH-1], d2_avg_out[c]}
              + {d2_max_out[c][DATA_WIDTH-1], d2_max_out[c]};
            if      (s > S17_HI) sig_in[c] = S17_HI[DATA_WIDTH-1:0];
            else if (s < S17_LO) sig_in[c] = S17_LO[DATA_WIDTH-1:0];
            else                 sig_in[c] = s[DATA_WIDTH-1:0];

            if      (sig_in[c] >  LUT_CLIP_HI) clipped[c] = LUT_CLIP_HI;
            else if (sig_in[c] <  LUT_CLIP_LO) clipped[c] = LUT_CLIP_LO;
            else                               clipped[c] = sig_in[c];
            addr[c] = ADDR_W'((clipped[c] + LUT_RANGE_Q) >>> LUT_SHIFT);
        end
    end

    logic signed [DATA_WIDTH-1:0] gate_reg [0:NUM_CH-1];

    always_ff @(posedge clk) begin
        if (rst) begin
            gate_valid <= 1'b0;
            for (int c = 0; c < NUM_CH; c++) begin
                gate_reg[c] <= '0;
                gate_out[c] <= '0;
            end
        end else begin
            gate_valid <= (x_valid && frame_last);
            if (x_valid && frame_last) begin
                for (int c = 0; c < NUM_CH; c++) begin
                    gate_reg[c] <= LUT[addr[c]];
                    gate_out[c] <= LUT[addr[c]];
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Phase 3: apply latched gate to re-streamed input.
    // -------------------------------------------------------------------------
    logic signed [ACC_WIDTH-1:0] apply_prod    [0:NUM_CH-1];
    logic signed [ACC_WIDTH-1:0] apply_shifted [0:NUM_CH-1];

    always_comb begin
        for (int c = 0; c < NUM_CH; c++) begin
            apply_prod[c]    = $signed(apply_x_in[c]) * $signed(gate_reg[c]);
            apply_shifted[c] = apply_prod[c] >>> FRAC_BITS;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            y_valid <= 1'b0;
            for (int c = 0; c < NUM_CH; c++) y_out[c] <= '0;
        end else begin
            y_valid <= apply_valid;
            if (apply_valid) begin
                for (int c = 0; c < NUM_CH; c++) begin
                    if      (apply_shifted[c] > SAT_HI) y_out[c] <= SAT_HI[DATA_WIDTH-1:0];
                    else if (apply_shifted[c] < SAT_LO) y_out[c] <= SAT_LO[DATA_WIDTH-1:0];
                    else                                y_out[c] <= apply_shifted[c][DATA_WIDTH-1:0];
                end
            end
        end
    end

endmodule
