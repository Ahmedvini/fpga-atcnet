// rtl/top_resource_eval.sv
//
// Resource-eval top that prevents Vivado from trimming your pipeline by:
// 1) Instantiating blocks end-to-end
// 2) Forcing NON-ZERO coefficients (so conv math isn't constant-zero)
// 3) Producing an anchored output (out_anchor) that depends on deep logic
//
// Notes:
// - This top assumes KERNEL_SIZE = 5 because the coefficient arrays below are length 5.
// - If you change KERNEL_SIZE later, you must update the coefficient arrays manually.

module top_resource_eval #(
  parameter int DATA_WIDTH  = 16,
  parameter int COEF_WIDTH  = 16,
  parameter int ACC_WIDTH   = 48,
  parameter int KERNEL_SIZE = 5,

  parameter int WINDOW_SIZE = 32,

  // Attention parameters
  parameter int NUM_CH     = 16,
  parameter int NUM_HEADS  = 4,
  parameter int ATTN_SHIFT = 4
)(
  input  logic                         clk,
  input  logic                         rst,

  input  logic                         in_valid,
  input  logic signed [DATA_WIDTH-1:0]  in_sample,

  output logic                         out_valid,
  output logic [31:0]                  out_anchor
);

  // ----------------------------
  // Derived
  // ----------------------------
  localparam int CH_PER_HEAD = (NUM_CH / NUM_HEADS);
  localparam int NUM_STREAMS = CH_PER_HEAD;

  // ----------------------------
  // Sanity check (keep only the safe one)
  // ----------------------------
  initial begin
    if ((NUM_CH % NUM_HEADS) != 0) begin
      $fatal(1, "NUM_CH must be divisible by NUM_HEADS.");
    end
    // Removed the KERNEL_SIZE string check that caused Vivado syntax issues.
  end

  // -------------------------------------------------------------------------
  // 1) window_gen
  // -------------------------------------------------------------------------
  logic                               window_valid;
  logic signed [DATA_WIDTH-1:0]        window [0:WINDOW_SIZE-1];

  window_gen #(
    .DATA_W(DATA_WIDTH),
    .WINDOW_SIZE(WINDOW_SIZE)
  ) u_window_gen (
    .clk(clk),
    .rst(rst),
    .in_valid(in_valid),
    .in_sample(in_sample),
    .window_valid(window_valid),
    .window(window)
  );

  // -------------------------------------------------------------------------
  // 2) window_reader
  // -------------------------------------------------------------------------
  logic signed [DATA_WIDTH-1:0] stream_sample;
  logic                         stream_valid;

  window_reader #(
    .DATA_WIDTH(DATA_WIDTH),
    .WINDOW_SIZE(WINDOW_SIZE)
  ) u_window_reader (
    .clk(clk),
    .rst(rst),
    .window_in(window),
    .window_valid(window_valid),
    .stream_out(stream_sample),
    .stream_valid(stream_valid)
  );

  // -------------------------------------------------------------------------
  // 3) NON-ZERO coefficients (note: arrays assume KERNEL_SIZE=5)
  // -------------------------------------------------------------------------
  localparam logic signed [COEF_WIDTH-1:0] DBC_COEFFS_A [KERNEL_SIZE] =
    '{16'sd1, 16'sd2, 16'sd3, 16'sd2, 16'sd1};

  localparam logic signed [COEF_WIDTH-1:0] DBC_COEFFS_B [KERNEL_SIZE] =
    '{16'sd1, 16'sd0, -16'sd1, 16'sd0, 16'sd1};

  // -------------------------------------------------------------------------
  // 4) dual_branch_conv
  // -------------------------------------------------------------------------
  logic signed [DATA_WIDTH-1:0] dbc_out;
  logic                         dbc_valid;

  dual_branch_conv #(
    .DATA_WIDTH(DATA_WIDTH),
    .COEF_WIDTH(COEF_WIDTH),
    .ACC_WIDTH(ACC_WIDTH),
    .KERNEL_SIZE(KERNEL_SIZE),
    .COEFFS_A(DBC_COEFFS_A),
    .COEFFS_B(DBC_COEFFS_B)
  ) u_dual_branch_conv (
    .clk(clk),
    .rst(rst),
    .x_in(stream_sample),
    .x_valid(stream_valid),
    .y_out(dbc_out),
    .y_valid(dbc_valid)
  );

  // -------------------------------------------------------------------------
  // 5) attention input vector
  // -------------------------------------------------------------------------
  logic signed [DATA_WIDTH-1:0] attn_in [0:NUM_CH-1];
  logic                         attn_in_valid;

  always_comb begin
    attn_in_valid = dbc_valid;
    for (int i = 0; i < NUM_CH; i++) begin
      attn_in[i] = dbc_out + $signed(i);
    end
  end

  // -------------------------------------------------------------------------
  // 6) temporal_multihead_attention
  // -------------------------------------------------------------------------
  logic signed [DATA_WIDTH-1:0] attn_out [0:CH_PER_HEAD-1];
  logic                         attn_valid;

  temporal_multihead_attention #(
    .DATA_WIDTH(DATA_WIDTH),
    .NUM_CH(NUM_CH),
    .NUM_HEADS(NUM_HEADS),
    .ATTN_SHIFT(ATTN_SHIFT)
  ) u_temporal_mha (
    .clk(clk),
    .rst(rst),
    .x_in(attn_in),
    .x_valid(attn_in_valid),
    .y_out(attn_out),
    .y_valid(attn_valid)
  );

  // -------------------------------------------------------------------------
  // 7) temporal_fusion coefficients (NUM_STREAMS = CH_PER_HEAD = 4 here)
  // -------------------------------------------------------------------------
  localparam logic signed [COEF_WIDTH-1:0] FUSION_COEFFS [0:NUM_STREAMS-1][KERNEL_SIZE] = '{
    '{16'sd1, 16'sd2, 16'sd3, 16'sd2, 16'sd1},
    '{16'sd1, 16'sd1, 16'sd1, 16'sd1, 16'sd1},
    '{16'sd2, 16'sd0, -16'sd2, 16'sd0, 16'sd2},
    '{16'sd1, 16'sd0, 16'sd0, 16'sd0, 16'sd1}
  };

  // fusion inputs
  logic signed [DATA_WIDTH-1:0] fusion_in [0:NUM_STREAMS-1];
  logic                         fusion_valid_in;

  always_comb begin
    fusion_valid_in = attn_valid;
    for (int s = 0; s < NUM_STREAMS; s++) begin
      fusion_in[s] = attn_out[s];
    end
  end

  logic signed [DATA_WIDTH-1:0] fusion_out;
  logic                         fusion_valid;

  temporal_fusion #(
    .DATA_WIDTH(DATA_WIDTH),
    .COEF_WIDTH(COEF_WIDTH),
    .ACC_WIDTH(ACC_WIDTH),
    .KERNEL_SIZE(KERNEL_SIZE),
    .NUM_STREAMS(NUM_STREAMS),
    .COEFFS(FUSION_COEFFS)
  ) u_temporal_fusion (
    .clk(clk),
    .rst(rst),
    .x_in(fusion_in),
    .x_valid(fusion_valid_in),
    .y_out(fusion_out),
    .y_valid(fusion_valid)
  );

  // -------------------------------------------------------------------------
  // 8) Anchor output
  // -------------------------------------------------------------------------
  logic [31:0] signature;

  always_comb begin
    signature = 32'hA5A5_1234 ^ {{(32-DATA_WIDTH){fusion_out[DATA_WIDTH-1]}}, fusion_out};
    signature = (signature << 5) ^ (signature >> 3) ^ 32'h1F00_00FF;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      out_valid  <= 1'b0;
      out_anchor <= 32'h0;
    end else begin
      out_valid <= fusion_valid;
      if (fusion_valid) out_anchor <= signature;
    end
  end

endmodule