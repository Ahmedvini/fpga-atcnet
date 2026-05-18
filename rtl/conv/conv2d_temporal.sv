// =============================================================================
// conv2d_temporal.sv
//
// Layer 1 of DB-ATCNet (PhysioNet variant): per-electrode temporal Conv2D.
//
//     Keras: Conv2D(filters=F1=16, kernel_size=(KE=64, 1),
//                   padding='same', use_bias=False)
//
// Numerical contract (bit-exact match against scripts/q88_layer1.py):
//   tap[k]   = (k==KE-1) ? in_sample : shift_reg[in_electrode][k+1]
//   acc[f]   = sum_{k=0..KE-1} signed(tap[k]) * signed(W[k][f])
//   out[f]   = sat(acc[f] >>> FRAC_BITS)  -> DATA_WIDTH (Q8.8)
//
// Streaming interface: feed (electrode, sample) tuples one per cycle. For
// padding='same' with stride 1, kernel 64, the caller must feed:
//   pad_top = (KE-1)/2 = 31 zero samples first   (warmup; out_valid stays low)
//   then real samples  t=0..TRIAL_SAMPLES-1     (each producing one output)
//   then pad_bot = 32 zero samples              (drains right-side pad)
// Output for input time T_in corresponds to model time t_out = T_in - 32.
//
// Resource note: the combinational MAC is 16 filters × 64 taps = 1024
// multiplies and a 64-input adder tree, evaluated each cycle. Synthesis on
// Z-7020 (220 DSPs) will spill into LUTs; on Ultrascale+ ZU3+ this fits.
// Add a TIME_MUX parameter later to serialize the filter dimension.
// =============================================================================

`timescale 1ns / 1ps

module conv2d_temporal #(
    parameter int NUM_EEG_CH    = 64,
    parameter int F1            = 16,
    parameter int KE            = 64,
    parameter int DATA_WIDTH    = 16,
    parameter int COEF_WIDTH    = 16,
    parameter int ACC_WIDTH     = 48,
    parameter int FRAC_BITS     = 8,
    // Path to .mem with KE*F1 signed Q-format coefficients, tap-major order:
    //   address k*F1 + f -> W[k][f]
    // Loaded once at elaboration via $readmemh.
    parameter string WEIGHTS_FILE = ""
) (
    input  logic clk,
    input  logic rst,

    input  logic                                 in_valid,
    input  logic [$clog2(NUM_EEG_CH)-1:0]        in_electrode,
    input  logic signed [DATA_WIDTH-1:0]         in_sample,

    output logic                                 out_valid,
    output logic [$clog2(NUM_EEG_CH)-1:0]        out_electrode,
    output logic signed [DATA_WIDTH-1:0]         out_filter [0:F1-1]
);

    // -------------------------------------------------------------------------
    // Weights: loaded once from WEIGHTS_FILE in tap-major, filter-minor order.
    // -------------------------------------------------------------------------
    logic signed [COEF_WIDTH-1:0] w_flat [0:KE*F1-1];
    logic signed [COEF_WIDTH-1:0] W      [0:KE-1][0:F1-1];

    initial begin
        if (WEIGHTS_FILE != "") begin
            $readmemh(WEIGHTS_FILE, w_flat);
        end else begin
            for (int i = 0; i < KE*F1; i++) w_flat[i] = '0;
        end
        for (int k = 0; k < KE; k++)
            for (int f = 0; f < F1; f++)
                W[k][f] = w_flat[k*F1 + f];
    end

    // -------------------------------------------------------------------------
    // Per-electrode shift register
    //   shift_reg[e][KE-1] = newest (most recently shifted in for electrode e)
    //   shift_reg[e][0]    = oldest
    // -------------------------------------------------------------------------
    logic signed [DATA_WIDTH-1:0] shift_reg [0:NUM_EEG_CH-1][0:KE-1];

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int e = 0; e < NUM_EEG_CH; e++)
                for (int k = 0; k < KE; k++)
                    shift_reg[e][k] <= '0;
        end else if (in_valid) begin
            shift_reg[in_electrode][KE-1] <= in_sample;
            for (int k = 0; k < KE - 1; k++)
                shift_reg[in_electrode][k] <= shift_reg[in_electrode][k+1];
        end
    end

    // -------------------------------------------------------------------------
    // Tap vector (post-update view): includes the new in_sample at index KE-1.
    // -------------------------------------------------------------------------
    logic signed [DATA_WIDTH-1:0] tap [0:KE-1];

    always_comb begin
        for (int k = 0; k < KE - 1; k++)
            tap[k] = shift_reg[in_electrode][k+1];
        tap[KE-1] = in_sample;
    end

    // -------------------------------------------------------------------------
    // 16 parallel MACs over 64 taps each
    // -------------------------------------------------------------------------
    logic signed [ACC_WIDTH-1:0] acc [0:F1-1];

    always_comb begin
        for (int f = 0; f < F1; f++) begin
            acc[f] = '0;
            for (int k = 0; k < KE; k++) begin
                acc[f] = acc[f] + $signed(tap[k]) * $signed(W[k][f]);
            end
        end
    end

    // -------------------------------------------------------------------------
    // Rescale (>>> FRAC_BITS) + symmetric saturation to DATA_WIDTH
    // -------------------------------------------------------------------------
    localparam logic signed [ACC_WIDTH-1:0] SAT_HI =
        (ACC_WIDTH)'((1 <<< (DATA_WIDTH-1)) - 1);
    localparam logic signed [ACC_WIDTH-1:0] SAT_LO =
        -(ACC_WIDTH)'(1 <<< (DATA_WIDTH-1));

    always_ff @(posedge clk) begin
        if (rst) begin
            out_valid     <= 1'b0;
            out_electrode <= '0;
            for (int f = 0; f < F1; f++) out_filter[f] <= '0;
        end else begin
            out_valid     <= in_valid;
            out_electrode <= in_electrode;
            for (int f = 0; f < F1; f++) begin
                logic signed [ACC_WIDTH-1:0] shifted;
                shifted = acc[f] >>> FRAC_BITS;
                if (shifted > SAT_HI)      out_filter[f] <= SAT_HI[DATA_WIDTH-1:0];
                else if (shifted < SAT_LO) out_filter[f] <= SAT_LO[DATA_WIDTH-1:0];
                else                       out_filter[f] <= shifted[DATA_WIDTH-1:0];
            end
        end
    end

endmodule
