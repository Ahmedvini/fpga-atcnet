// =============================================================================
// cbam_spatial_attn.sv  —  ImpCBAM SPATIAL attention block (one sliding window).
//
// Bit-exact match to scripts/q88_layer17_spatial.py (HW-aligned variant):
//
//   Phase 1 (input stream, T_WIN cycles, frame_last on the last vector):
//     avg_sum[t] = sum_c  x[t,c]                       // Q8.8 accumulator
//     max_acc[t] = max_c  x[t,c]
//     norm[t]    = sum_c |x[t,c]|                      // unsigned for divider
//     q_sum[t]   = sum_c |x[t,c]| * x[t,c]             // 32-bit signed
//
//   Then sequential FSM:
//     For each t in 0..T_WIN-1, do one floor division:
//       inv_norm[t] = (1<<24) / max(norm[t], 1)
//     Compute:
//       avg[t]   = sat( avg_sum[t] >>> log2(NUM_CH) )           // NUM_CH=32 → >>>5
//       max[t]   = max_acc[t]
//       stoch[t] = sat( (inv_norm[t] * q_sum[t]) >>> 24 )       // both signed
//       concat[t,ic] = {avg, max, stoch}[ic]
//
//     Conv2D(KH, KW, IC_CAT, 1) "same" on (T_WIN, 1, IC_CAT). Because the W-dim
//     of the input is 1, only the kw = (KW-1)/2 column of the kernel contributes
//     (others multiply zero-pads). The 1D collapsed kernel `qw_slice[kh, ic]`
//     is what we store in the WEIGHTS file.
//       acc[t]   = sum_{kh=0..KH-1, ic=0..IC_CAT-1}
//                       cat_pad[t + kh, ic] * qw_slice[kh, ic]
//       sig_in[t]= sat( acc[t] >>> FRAC_BITS )
//       gate[t]  = sigmoid_LUT(sig_in[t])
//
//   Phase 2 (re-streamed input, T_WIN cycles, apply_valid):
//     y[t,c]   = sat( x[t,c] * gate[t] >>> FRAC_BITS )
//
// Per-window latency from the frame_last pulse to gate_valid is approximately
// (Q_WIDTH+3) * T_WIN ≈ 200 cycles (divisions are the dominant cost). The TB
// can poll gate_valid before re-streaming.
//
// =============================================================================

`timescale 1ns / 1ps

module cbam_spatial_attn #(
    parameter int    DATA_WIDTH    = 16,
    parameter int    COEF_WIDTH    = 16,
    parameter int    FRAC_BITS     = 8,
    parameter int    NUM_CH        = 32,
    parameter int    LOG2_NUM_CH   = 5,
    parameter int    T_WIN         = 6,
    parameter int    KH            = 7,
    parameter int    IC_CAT        = 3,
    parameter int    NORM_WIDTH    = 25,           // need ≥ 25 bits to hold 2^24 numerator
    parameter int    INV_N_WIDTH   = 32,
    parameter int    QSUM_WIDTH    = 40,           // sum_c |x|*x, signed
    parameter int    LUT_N         = 1024,
    parameter int    LUT_RANGE_Q   = 1024,
    parameter int    LUT_SHIFT     = 1,
    parameter int    N_WIN         = 1,
    parameter string CONV_W_FILE   = "",
    parameter string LUT_FILE      = ""
) (
    input  logic                              clk,
    input  logic                              rst,

    // Selects per-window weight bank.
    input  logic [$clog2(N_WIN > 1 ? N_WIN : 2)-1:0] window_idx,

    // Phase 1: streaming input (T_WIN vectors, frame_last on the last).
    input  logic signed [DATA_WIDTH-1:0]      x_in [0:NUM_CH-1],
    input  logic                              x_valid,
    input  logic                              frame_last,

    // Gate ready pulse (1 cycle) after the FSM finishes.
    output logic                              gate_valid,
    output logic signed [DATA_WIDTH-1:0]      gate_out [0:T_WIN-1],

    // Phase 2: re-streamed input. TB pulses apply_valid for each of the
    // T_WIN vectors in order. DUT tracks the index internally.
    input  logic signed [DATA_WIDTH-1:0]      apply_x_in [0:NUM_CH-1],
    input  logic                              apply_valid,
    output logic signed [DATA_WIDTH-1:0]      y_out [0:NUM_CH-1],
    output logic                              y_valid
);

    // -------------------------------------------------------------------------
    // Weights + LUT
    // -------------------------------------------------------------------------
    localparam int CW_STRIDE = KH * IC_CAT;
    logic signed [COEF_WIDTH-1:0] CW  [0:N_WIN * CW_STRIDE - 1];   // (bank, kh, ic) flat
    wire   [31:0] cw_base = window_idx * CW_STRIDE;
    logic signed [DATA_WIDTH-1:0] LUT [0:LUT_N - 1];
    initial begin
        if (CONV_W_FILE != "") $readmemh(CONV_W_FILE, CW);
        if (LUT_FILE    != "") $readmemh(LUT_FILE,    LUT);
    end

    localparam logic signed [31:0] SAT_HI_32 =  (1 <<< (DATA_WIDTH-1)) - 1;
    localparam logic signed [31:0] SAT_LO_32 = -(1 <<< (DATA_WIDTH-1));

    // -------------------------------------------------------------------------
    // Phase 1: per-t descriptors
    // -------------------------------------------------------------------------
    logic signed [31:0] avg_sum [0:T_WIN-1];
    logic signed [DATA_WIDTH-1:0] max_acc_arr [0:T_WIN-1];
    logic        [NORM_WIDTH-1:0] norm_arr    [0:T_WIN-1];
    logic signed [QSUM_WIDTH-1:0] qsum_arr    [0:T_WIN-1];

    logic [$clog2(T_WIN+1)-1:0] t_idx;     // counts incoming vectors

    // Combinational per-vector reductions over c.
    logic signed [31:0]            cur_avg_sum;
    logic signed [DATA_WIDTH-1:0]  cur_max;
    logic [NORM_WIDTH-1:0]         cur_norm;
    logic signed [QSUM_WIDTH-1:0]  cur_qsum;
    localparam logic signed [DATA_WIDTH-1:0] DATA_MIN = {1'b1, {(DATA_WIDTH-1){1'b0}}};

    always_comb begin
        cur_avg_sum = '0;
        cur_max     = DATA_MIN;
        cur_norm    = '0;
        cur_qsum    = '0;
        for (int c = 0; c < NUM_CH; c++) begin
            automatic logic signed [DATA_WIDTH-1:0] xc = x_in[c];
            automatic logic signed [DATA_WIDTH-1:0] ax;
            cur_avg_sum = cur_avg_sum + $signed({{(32-DATA_WIDTH){xc[DATA_WIDTH-1]}}, xc});
            if (xc > cur_max) cur_max = xc;
            ax = (xc < 0) ? -xc : xc;
            cur_norm = cur_norm + NORM_WIDTH'(ax);
            cur_qsum = cur_qsum + $signed({{(QSUM_WIDTH-DATA_WIDTH){ax[DATA_WIDTH-1]}}, ax})
                                * $signed({{(QSUM_WIDTH-DATA_WIDTH){xc[DATA_WIDTH-1]}}, xc});
        end
    end

    // -------------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        S_IDLE,
        S_ACCUM,          // collecting input
        S_DIV_START,
        S_DIV_WAIT,
        S_DESCRIPTORS,    // build avg/stoch/concat (sequential per t for simplicity)
        S_CONV,           // 7-tap MAC per t
        S_GATE,           // sigmoid LUT
        S_READY
    } state_t;
    state_t state;

    logic [$clog2(T_WIN+1)-1:0] fsm_t;

    // Divider instance (shared across all T_WIN divisions).
    logic                    div_start;
    logic [NORM_WIDTH-1:0]   div_num_hi_lo; // not actually used (num is fixed 1<<24)
    logic [NORM_WIDTH-1:0]   div_denom;
    logic                    div_busy, div_done;
    logic [NORM_WIDTH-1:0]   div_q;
    logic [NORM_WIDTH-1:0]   div_r;

    serial_divider #(.N_WIDTH(NORM_WIDTH), .D_WIDTH(NORM_WIDTH), .Q_WIDTH(NORM_WIDTH)) u_div (
        .clk(clk), .rst(rst),
        .start(div_start),
        .numerator(NORM_WIDTH'(1 <<< 24)),
        .denominator(div_denom),
        .busy(div_busy), .done(div_done),
        .quotient(div_q), .remainder(div_r)
    );

    logic [NORM_WIDTH-1:0]      inv_norm_arr [0:T_WIN-1];
    logic signed [DATA_WIDTH-1:0] avg_arr  [0:T_WIN-1];
    logic signed [DATA_WIDTH-1:0] stoch_arr[0:T_WIN-1];
    logic signed [DATA_WIDTH-1:0] cat_arr  [0:T_WIN-1][0:IC_CAT-1];
    logic signed [DATA_WIDTH-1:0] sig_in_arr [0:T_WIN-1];

    // Conv accumulator scratch
    logic signed [47:0] conv_acc;
    logic signed [47:0] conv_shifted;
    logic signed [DATA_WIDTH-1:0] gate_reg [0:T_WIN-1];

    // Phase 2 counter
    logic [$clog2(T_WIN+1)-1:0] apply_idx;

    // Saturate helpers (inline)
    function automatic logic signed [DATA_WIDTH-1:0] sat_q88 (input logic signed [47:0] v);
        if      (v > SAT_HI_32) return SAT_HI_32[DATA_WIDTH-1:0];
        else if (v < SAT_LO_32) return SAT_LO_32[DATA_WIDTH-1:0];
        else                    return v[DATA_WIDTH-1:0];
    endfunction

    // Sigmoid LUT addressing
    localparam int ADDR_W = $clog2(LUT_N);
    function automatic logic [ADDR_W-1:0] lut_addr (input logic signed [DATA_WIDTH-1:0] v);
        logic signed [DATA_WIDTH-1:0] clipped;
        if      (v >  (LUT_RANGE_Q-1)) clipped = LUT_RANGE_Q - 1;
        else if (v <  -LUT_RANGE_Q)    clipped = -LUT_RANGE_Q;
        else                           clipped = v;
        return ADDR_W'((clipped + LUT_RANGE_Q) >>> LUT_SHIFT);
    endfunction

    always_ff @(posedge clk) begin
        if (rst) begin
            state      <= S_IDLE;
            t_idx      <= 0;
            fsm_t      <= 0;
            gate_valid <= 1'b0;
            y_valid    <= 1'b0;
            div_start  <= 1'b0;
            div_denom  <= '0;
            apply_idx  <= 0;
            for (int t = 0; t < T_WIN; t++) begin
                avg_sum[t]     <= '0;
                max_acc_arr[t] <= DATA_MIN;
                norm_arr[t]    <= '0;
                qsum_arr[t]    <= '0;
                inv_norm_arr[t] <= '0;
                avg_arr[t]     <= '0;
                stoch_arr[t]   <= '0;
                sig_in_arr[t]  <= '0;
                gate_reg[t]    <= '0;
                gate_out[t]    <= '0;
                for (int ic = 0; ic < IC_CAT; ic++) cat_arr[t][ic] <= '0;
            end
            for (int c = 0; c < NUM_CH; c++) y_out[c] <= '0;
        end else begin
            gate_valid <= 1'b0;
            y_valid    <= 1'b0;
            div_start  <= 1'b0;

            unique case (state)
                S_IDLE: begin
                    if (x_valid) begin
                        t_idx              <= 1;
                        avg_sum[0]         <= cur_avg_sum;
                        max_acc_arr[0]     <= cur_max;
                        norm_arr[0]        <= cur_norm;
                        qsum_arr[0]        <= cur_qsum;
                        state              <= (frame_last) ? S_DIV_START : S_ACCUM;
                        if (frame_last) fsm_t <= 0;
                    end
                end
                S_ACCUM: begin
                    if (x_valid) begin
                        avg_sum[t_idx]      <= cur_avg_sum;
                        max_acc_arr[t_idx]  <= cur_max;
                        norm_arr[t_idx]     <= cur_norm;
                        qsum_arr[t_idx]     <= cur_qsum;
                        if (frame_last) begin
                            fsm_t <= 0;
                            state <= S_DIV_START;
                        end else begin
                            t_idx <= t_idx + 1;
                        end
                    end
                end
                S_DIV_START: begin
                    // Floor denom to 1 to avoid /0; multiplexer arms divider.
                    div_denom <= (norm_arr[fsm_t] == '0) ? NORM_WIDTH'(1) : norm_arr[fsm_t];
                    div_start <= 1'b1;
                    state     <= S_DIV_WAIT;
                end
                S_DIV_WAIT: begin
                    if (div_done) begin
                        inv_norm_arr[fsm_t] <= div_q;
                        if (fsm_t == T_WIN - 1) begin
                            state <= S_DESCRIPTORS;
                            fsm_t <= 0;
                        end else begin
                            fsm_t <= fsm_t + 1;
                            state <= S_DIV_START;
                        end
                    end
                end
                S_DESCRIPTORS: begin
                    // For one t per cycle, compute avg / stoch / concat.
                    automatic logic signed [47:0] avg_full;
                    automatic logic signed [47:0] stoch_full;
                    avg_full   = $signed(avg_sum[fsm_t]) >>> LOG2_NUM_CH;
                    avg_arr[fsm_t]   <= sat_q88(avg_full);
                    stoch_full = ($signed({{(48-NORM_WIDTH){1'b0}}, inv_norm_arr[fsm_t]})
                                  * qsum_arr[fsm_t]) >>> 24;
                    stoch_arr[fsm_t] <= sat_q88(stoch_full);
                    cat_arr[fsm_t][0] <= sat_q88(avg_full);
                    cat_arr[fsm_t][1] <= max_acc_arr[fsm_t];
                    cat_arr[fsm_t][2] <= sat_q88(stoch_full);
                    if (fsm_t == T_WIN - 1) begin
                        state <= S_CONV;
                        fsm_t <= 0;
                    end else begin
                        fsm_t <= fsm_t + 1;
                    end
                end
                S_CONV: begin
                    // 7-tap MAC for output time fsm_t.
                    automatic logic signed [47:0] acc;
                    automatic int t_cat_idx;
                    automatic int pad_top = (KH - 1) / 2;
                    acc = '0;
                    for (int kh = 0; kh < KH; kh++) begin
                        t_cat_idx = fsm_t + kh - pad_top;
                        if (t_cat_idx >= 0 && t_cat_idx < T_WIN) begin
                            for (int ic = 0; ic < IC_CAT; ic++) begin
                                acc = acc + $signed(cat_arr[t_cat_idx][ic])
                                          * $signed(CW[cw_base + kh * IC_CAT + ic]);
                            end
                        end
                    end
                    sig_in_arr[fsm_t] <= sat_q88(acc >>> FRAC_BITS);
                    if (fsm_t == T_WIN - 1) begin
                        state <= S_GATE;
                        fsm_t <= 0;
                    end else begin
                        fsm_t <= fsm_t + 1;
                    end
                end
                S_GATE: begin
                    for (int t = 0; t < T_WIN; t++) begin
                        gate_reg[t] <= LUT[lut_addr(sig_in_arr[t])];
                        gate_out[t] <= LUT[lut_addr(sig_in_arr[t])];
                    end
                    gate_valid <= 1'b1;
                    state      <= S_READY;
                end
                S_READY: begin
                    // Stay; phase 2 driven by apply_valid in parallel.
                end
                default: state <= S_IDLE;
            endcase

            // -----------------------------------------------------------------
            // Phase 2: gate apply (runs concurrently with S_READY state).
            // After T_WIN outputs are emitted, drop back to S_IDLE so the
            // next window's first x_valid is treated as a fresh frame.
            // -----------------------------------------------------------------
            if (state == S_READY && apply_valid) begin
                for (int c = 0; c < NUM_CH; c++) begin
                    automatic logic signed [31:0] p;
                    p = $signed(apply_x_in[c]) * $signed(gate_reg[apply_idx]);
                    p = p >>> FRAC_BITS;
                    y_out[c] <= sat_q88({{16{p[31]}}, p});
                end
                y_valid   <= 1'b1;
                if (apply_idx == T_WIN - 1) begin
                    apply_idx <= '0;
                    state     <= S_IDLE;
                end else begin
                    apply_idx <= apply_idx + 1;
                end
            end
        end
    end

endmodule
