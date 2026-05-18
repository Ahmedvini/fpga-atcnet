// =============================================================================
// dense_classifier.sv  —  Per-window Dense(F → N_CLS) classifier.
//
//   logits[o] = sat( (sum_i x[i] * W[o, i]) >>> FRAC_BITS + b[o] )
//
// Weights loaded via $readmemh from WEIGHTS_FILE (row-major (Nout, Nin)),
// bias from BIAS_FILE (Nout entries). 1-cycle combinational MAC array
// (Nin*Nout multiplies, fully parallel — for F=32, N_CLS=2 that's 64
// 16x16-bit DSPs, fine for both Z7020 and US+).
//
// Latency: 1 cycle from `in_valid` to `out_valid`.
// =============================================================================

`timescale 1ns / 1ps

module dense_classifier #(
    parameter int    DATA_WIDTH = 16,
    parameter int    COEF_WIDTH = 16,
    parameter int    ACC_WIDTH  = 40,
    parameter int    FRAC_BITS  = 8,
    parameter int    F          = 32,
    parameter int    N_CLS      = 2,
    parameter string WEIGHTS_FILE = "",
    parameter string BIAS_FILE    = ""
) (
    input  logic                              clk,
    input  logic                              rst,

    input  logic signed [DATA_WIDTH-1:0]      x_in [0:F-1],
    input  logic                              in_valid,

    output logic signed [DATA_WIDTH-1:0]      logits   [0:N_CLS-1],
    output logic                              out_valid
);

    logic signed [COEF_WIDTH-1:0] W [0:N_CLS * F - 1];   // (o, i) row-major
    logic signed [DATA_WIDTH-1:0] B [0:N_CLS - 1];
    initial begin
        if (WEIGHTS_FILE != "") $readmemh(WEIGHTS_FILE, W);
        if (BIAS_FILE    != "") $readmemh(BIAS_FILE,    B);
    end

    localparam logic signed [ACC_WIDTH-1:0] SAT_HI =
        (ACC_WIDTH)'((1 <<< (DATA_WIDTH-1)) - 1);
    localparam logic signed [ACC_WIDTH-1:0] SAT_LO =
        -(ACC_WIDTH)'(1 <<< (DATA_WIDTH-1));

    function automatic logic signed [DATA_WIDTH-1:0] sat_q88 (input logic signed [ACC_WIDTH-1:0] v);
        if      (v > SAT_HI) return SAT_HI[DATA_WIDTH-1:0];
        else if (v < SAT_LO) return SAT_LO[DATA_WIDTH-1:0];
        else                 return v[DATA_WIDTH-1:0];
    endfunction

    logic signed [ACC_WIDTH-1:0] acc [0:N_CLS-1];
    logic signed [ACC_WIDTH-1:0] shifted [0:N_CLS-1];

    always_comb begin
        for (int o = 0; o < N_CLS; o++) begin
            acc[o] = '0;
            for (int i = 0; i < F; i++) begin
                acc[o] = acc[o] + $signed(x_in[i]) * $signed(W[o * F + i]);
            end
            shifted[o] = (acc[o] >>> FRAC_BITS)
                       + $signed({{(ACC_WIDTH-DATA_WIDTH){B[o][DATA_WIDTH-1]}}, B[o]});
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            out_valid <= 1'b0;
            for (int o = 0; o < N_CLS; o++) logits[o] <= '0;
        end else begin
            out_valid <= in_valid;
            if (in_valid) begin
                for (int o = 0; o < N_CLS; o++) logits[o] <= sat_q88(shifted[o]);
            end
        end
    end

endmodule
