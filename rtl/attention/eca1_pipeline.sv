// =============================================================================
// eca1_pipeline.sv  —  ECA₁ orchestrator for HaLT DB-ATCNet.
//
// Wraps gap_accumulator + eca_attention + gate_apply with an internal buffer
// so a single stream of N_FRAMES (T*C) Q8.8 vectors can be ingested, the
// per-channel gate computed, and the buffer replayed through gate_apply
// to produce the gated output stream.
//
//   Phase 1 (INGEST): N_FRAMES cycles, one (NUM_CH)-wide x_in per cycle.
//                     On cycle N_FRAMES-1 frame_last fires internally;
//                     gap_acc emits gap_valid one cycle later.
//   Phase 2 (GATE)  : eca_attention turns the GAP vector into a per-channel
//                     gate (1-cycle latency).
//   Phase 3 (REPLAY): N_FRAMES cycles, output the buffered input multiplied
//                     by the latched gate. y_valid pulses each cycle.
//   `done` pulses once when REPLAY completes.
//
// Buffer: NUM_CH-wide × N_FRAMES deep. For ECA₁ N_FRAMES=T*C=3000, NUM_CH=16
//         → 48000 Q8.8 entries = 96 KB (fits in Z-7020's BRAM budget).
//
// Bit-exact match to scripts/q88_eca1.py.
// =============================================================================

`timescale 1ns / 1ps

module eca1_pipeline #(
    parameter int    DATA_WIDTH  = 16,
    parameter int    NUM_CH      = 16,
    parameter int    KECA        = 3,
    parameter int    N_FRAMES    = 3000,           // T * C for ECA₁
    parameter int    INV_N       = 5592,           // round(2^24 / N_FRAMES)
    parameter int    INV_N_SHIFT = 24,
    parameter int    INV_N_WIDTH = 24,
    parameter int    LUT_N       = 1024,
    parameter int    LUT_RANGE_Q = 1024,
    parameter int    LUT_SHIFT   = 1,
    parameter string WEIGHTS_FILE = "",
    parameter string LUT_FILE     = ""
) (
    input  logic                            clk,
    input  logic                            rst,

    // Streaming input — drive N_FRAMES cycles of x_valid back-to-back. The
    // last cycle should set in_last; the module ignores any further x_valid
    // until the current inference completes (`done` pulse).
    input  logic signed [DATA_WIDTH-1:0]    x_in [0:NUM_CH-1],
    input  logic                            x_valid,

    output logic signed [DATA_WIDTH-1:0]    y_out [0:NUM_CH-1],
    output logic                            y_valid,
    output logic                            done
);

    // -------------------------------------------------------------------------
    // Internal buffer (3000 × 16 Q8.8 for ECA₁).
    // -------------------------------------------------------------------------
    logic signed [DATA_WIDTH-1:0] buf_mem [0:N_FRAMES-1][0:NUM_CH-1];

    // -------------------------------------------------------------------------
    // Counters / FSM
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {S_IDLE, S_INGEST, S_WAIT_GATE, S_REPLAY, S_DONE} state_t;
    state_t state;

    logic [$clog2(N_FRAMES+1)-1:0] cnt;
    // frame_last must be combinational so gap_accumulator sees (x_valid &&
    // frame_last) on the SAME cycle as the last ingestion sample.
    wire frame_last_internal = (state == S_INGEST) && (cnt == N_FRAMES - 1);

    // -------------------------------------------------------------------------
    // GAP accumulator
    // -------------------------------------------------------------------------
    logic                         gap_valid;
    logic signed [DATA_WIDTH-1:0] gap_out [0:NUM_CH-1];

    gap_accumulator #(
        .DATA_WIDTH(DATA_WIDTH), .NUM_CH(NUM_CH), .ACC_WIDTH(32),
        .INV_N(INV_N), .INV_N_SHIFT(INV_N_SHIFT), .INV_N_WIDTH(INV_N_WIDTH)
    ) u_gap (
        .clk(clk), .rst(rst),
        .x_in(x_in), .x_valid(state == S_INGEST && x_valid),
        .frame_last(frame_last_internal),
        .gap_out(gap_out), .gap_valid(gap_valid)
    );

    // -------------------------------------------------------------------------
    // ECA attention (Conv1D + sigmoid LUT) — 1-cycle latency on gap_valid.
    // -------------------------------------------------------------------------
    logic                         gate_valid;
    logic signed [DATA_WIDTH-1:0] gate_out [0:NUM_CH-1];

    eca_attention #(
        .DATA_WIDTH(DATA_WIDTH), .COEF_WIDTH(16), .ACC_WIDTH(48), .FRAC_BITS(8),
        .NUM_CH(NUM_CH), .KECA(KECA),
        .LUT_N(LUT_N), .LUT_RANGE_Q(LUT_RANGE_Q), .LUT_SHIFT(LUT_SHIFT),
        .WEIGHTS_FILE(WEIGHTS_FILE), .LUT_FILE(LUT_FILE)
    ) u_eca (
        .clk(clk), .rst(rst),
        .gap_in(gap_out), .gap_valid(gap_valid),
        .gate_out(gate_out), .gate_valid(gate_valid)
    );

    // Latched gate.
    logic signed [DATA_WIDTH-1:0] gate_latched [0:NUM_CH-1];

    // -------------------------------------------------------------------------
    // Gate apply (per-channel multiplier).
    // -------------------------------------------------------------------------
    logic signed [DATA_WIDTH-1:0] apply_x [0:NUM_CH-1];
    logic                         apply_valid;
    logic signed [DATA_WIDTH-1:0] apply_y [0:NUM_CH-1];
    logic                         apply_y_valid;

    gate_apply #(
        .DATA_WIDTH(DATA_WIDTH), .NUM_CH(NUM_CH), .FRAC_BITS(8), .ACC_WIDTH(32)
    ) u_apply (
        .clk(clk), .rst(rst),
        .x_in(apply_x), .x_valid(apply_valid),
        .gate_in(gate_latched),
        .y_out(apply_y), .y_valid(apply_y_valid)
    );

    // -------------------------------------------------------------------------
    // Main FSM + buffer write/read
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            cnt   <= 0;
            apply_valid <= 1'b0;
            y_valid     <= 1'b0;
            done        <= 1'b0;
            for (int i = 0; i < NUM_CH; i++) begin
                gate_latched[i] <= '0;
                apply_x[i]      <= '0;
                y_out[i]        <= '0;
            end
        end else begin
            // Defaults that pulse for one cycle.
            done    <= 1'b0;
            y_valid <= 1'b0;

            unique case (state)
                S_IDLE: begin
                    apply_valid <= 1'b0;
                    if (x_valid) begin
                        // First sample of new frame.
                        for (int i = 0; i < NUM_CH; i++) buf_mem[0][i] <= x_in[i];
                        cnt   <= 1;
                        state <= S_INGEST;
                    end
                end
                S_INGEST: begin
                    if (x_valid) begin
                        for (int i = 0; i < NUM_CH; i++) buf_mem[cnt][i] <= x_in[i];
                        if (cnt == N_FRAMES - 1) begin
                            cnt   <= 0;
                            state <= S_WAIT_GATE;
                        end else begin
                            cnt <= cnt + 1;
                        end
                    end
                end
                S_WAIT_GATE: begin
                    if (gate_valid) begin
                        for (int i = 0; i < NUM_CH; i++) gate_latched[i] <= gate_out[i];
                        cnt   <= 0;
                        state <= S_REPLAY;
                    end
                end
                S_REPLAY: begin
                    // Drive apply_valid for the buffer entry; gate_apply
                    // emits y_out one cycle later.
                    apply_valid <= 1'b1;
                    for (int i = 0; i < NUM_CH; i++) apply_x[i] <= buf_mem[cnt][i];
                    if (cnt == N_FRAMES - 1) begin
                        cnt   <= 0;
                        state <= S_DONE;
                    end else begin
                        cnt <= cnt + 1;
                    end
                end
                S_DONE: begin
                    apply_valid <= 1'b0;
                    // Wait one extra cycle to flush the final gate_apply output.
                    if (apply_y_valid) begin
                        // Last output emitted this cycle — propagate it.
                    end else begin
                        done  <= 1'b1;
                        state <= S_IDLE;
                    end
                end
                default: state <= S_IDLE;
            endcase

            // Pass through gate_apply outputs as the streaming pipeline output.
            if (apply_y_valid) begin
                for (int i = 0; i < NUM_CH; i++) y_out[i] <= apply_y[i];
                y_valid <= 1'b1;
            end
        end
    end

endmodule
