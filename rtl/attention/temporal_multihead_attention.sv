/**
 * Module: temporal_multihead_attention
 * 
 * Description:
 *   Hardware-aware approximation of multi-head temporal attention.
 *   
 *   Operation:
 *   1. Splits input channels into N heads.
 *   2. Computes an "energy" score (attention weight) for each head using L1 norm (sum of absolute values).
 *   3. Modulates (scales) each head's channels by its attention weight.
 *   4. Sums the corresponding channels across all heads to produce the output.
 *      Output dimension = NUM_CH / NUM_HEADS.
 * 
 *   Input:  [NUM_HEADS * CH_PER_HEAD]
 *   Output: [CH_PER_HEAD]
 * 
 * Latency:
 *   Cycle 1: Energy Calculation (Sum abs).
 *   Cycle 2: Modulation (Mult).
 *   Cycle 3: Aggregation (Sum heads).
 *   Total: 3 cycles.
 */

module temporal_multihead_attention #(
    parameter int DATA_WIDTH = 16,
    parameter int NUM_CH     = 16, // Total input channels
    parameter int NUM_HEADS  = 4,  // Number of heads
    parameter int ATTN_SHIFT = 4   // Right shift for attention score normalization
) (
    input  logic clk,
    input  logic rst,

    // Streaming Input
    input  logic signed [DATA_WIDTH-1:0] x_in [0:NUM_CH-1],
    input  logic                         x_valid,

    // Streaming Output
    // Output dimension is reduced by factor of NUM_HEADS (aggregation)
    output logic signed [DATA_WIDTH-1:0] y_out [0:(NUM_CH/NUM_HEADS)-1],
    output logic                         y_valid
);

    // -------------------------------------------------------------------------
    // Validate Parameters (Elaboration Time)
    // -------------------------------------------------------------------------
    generate
        if ((NUM_CH % NUM_HEADS) != 0) begin : gen_param_error
            $error("NUM_CH (%0d) must be divisible by NUM_HEADS (%0d).", NUM_CH, NUM_HEADS);
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Parameters & Derived Types
    // -------------------------------------------------------------------------
    localparam int CH_PER_HEAD = NUM_CH / NUM_HEADS;
    
    // Width for energy sum. Worst case: CH_PER_HEAD * MaxVal.
    // Roughly DATA_WIDTH + log2(CH_PER_HEAD).
    localparam int ENERGY_WIDTH = DATA_WIDTH + $clog2(CH_PER_HEAD) + 1; // +1 for safety
    
    // Product Width
    localparam int PROD_WIDTH = DATA_WIDTH + ENERGY_WIDTH;
    
        // Aggregation Accumulator Width
    localparam int AGG_WIDTH = DATA_WIDTH + $clog2(NUM_HEADS); // Allow growth by sum of heads

    // -------------------------------------------------------------------------
    // Pipeline Registers
    // -------------------------------------------------------------------------

    // Stage 1 Registers: Energy Calculation Results & Data storage
    logic [ENERGY_WIDTH-1:0]        head_energy_reg  [0:NUM_HEADS-1];
    logic signed [DATA_WIDTH-1:0]   x_d1_reg         [0:NUM_CH-1];
    logic                           valid_d1_reg;

    // Stage 2 Registers: Modulated Data
    logic signed [DATA_WIDTH-1:0]   head_modulated_reg [0:NUM_HEADS-1][0:CH_PER_HEAD-1];
    logic                           valid_d2_reg;

    // Stage 3 Registers: Output (y_out, y_valid declared in ports)

    // -------------------------------------------------------------------------
    // Intermediate Signal Declarations (Combinational)
    // -------------------------------------------------------------------------

    // Stage 1 Intermediate Signals
    logic [ENERGY_WIDTH-1:0]        head_energy_comb [0:NUM_HEADS-1];
    logic [ENERGY_WIDTH-1:0]        energy_accum     [0:NUM_HEADS-1]; // Accumulator for L1 norm

    // Stage 2 Intermediate Signals
    logic signed [PROD_WIDTH-1:0]   prod_comb [0:NUM_HEADS-1][0:CH_PER_HEAD-1];
    // Stage 3 Intermediate Signals
    logic signed [AGG_WIDTH:0]      agg_comb [0:CH_PER_HEAD-1]; // +1 for safety during sum

    // -------------------------------------------------------------------------
    // Stage 1: Energy Calculation (L1 Norm Proxy)
    // -------------------------------------------------------------------------
    
    always_comb begin
        for (int h = 0; h < NUM_HEADS; h++) begin
            energy_accum[h] = '0;
            for (int c = 0; c < CH_PER_HEAD; c++) begin
                // L1 Norm: Accumulate absolute values
                if (x_in[h*CH_PER_HEAD + c] < 0) begin
                    energy_accum[h] = energy_accum[h] + (-x_in[h*CH_PER_HEAD + c]);
                end else begin
                    energy_accum[h] = energy_accum[h] + x_in[h*CH_PER_HEAD + c];
                end
            end
            // Normalization shift (Logic shift for unsigned energy)
            head_energy_comb[h] = energy_accum[h] >> ATTN_SHIFT;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int h=0; h < NUM_HEADS; h++) head_energy_reg[h] <= '0;
            valid_d1_reg <= 1'b0;
            for (int i=0; i < NUM_CH; i++) x_d1_reg[i] <= '0;
        end else begin
            valid_d1_reg <= x_valid;
            
            if (x_valid) begin
                // Update Energy
                head_energy_reg <= head_energy_comb;
                // Pipeline Input Data
                x_d1_reg <= x_in;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Stage 2: Modulation (Multiply by Attention Weight)
    // -------------------------------------------------------------------------
    
    always_comb begin
        for (int h = 0; h < NUM_HEADS; h++) begin
            for (int c = 0; c < CH_PER_HEAD; c++) begin
                // Signed Data * Unsigned Energy = Signed Product
                // Force signed context for correct arithmetic.
                prod_comb[h][c] = x_d1_reg[h*CH_PER_HEAD + c] * signed'({1'b0, head_energy_reg[h]});
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
             for (int h=0; h < NUM_HEADS; h++) 
                for (int c=0; c < CH_PER_HEAD; c++) 
                    head_modulated_reg[h][c] <= '0;
             valid_d2_reg <= 1'b0;
        end else begin
            valid_d2_reg <= valid_d1_reg;
            
            if (valid_d1_reg) begin
                for (int h = 0; h < NUM_HEADS; h++) begin
                    for (int c = 0; c < CH_PER_HEAD; c++) begin
                        // MSB Extraction / Normalization
                        // Taking top bits to return to DATA_WIDTH.
                        head_modulated_reg[h][c] <= prod_comb[h][c][PROD_WIDTH-1 -: DATA_WIDTH];
                    end
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Stage 3: Aggregation (Sum Heads)
    // -------------------------------------------------------------------------
    
    always_comb begin
        for (int c = 0; c < CH_PER_HEAD; c++) begin
            agg_comb[c] = '0; 
            for (int h = 0; h < NUM_HEADS; h++) begin
                agg_comb[c] = agg_comb[c] + head_modulated_reg[h][c];
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int c=0; c < CH_PER_HEAD; c++) y_out[c] <= '0;
            y_valid <= 1'b0;
        end else begin
            y_valid <= valid_d2_reg;
            
            if (valid_d2_reg) begin
                for (int c = 0; c < CH_PER_HEAD; c++) begin
                    // Final Assignment (MSB Extraction for Averaging effect)
                    // Normalizes the sum growth by taking the upper bits.
                    y_out[c] <= agg_comb[c][AGG_WIDTH -: DATA_WIDTH]; 
                end
            end
        end
    end

endmodule
