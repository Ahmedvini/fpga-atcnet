module window_gen #(
    parameter int DATA_W = 16,            // width of one sample
    parameter int WINDOW_SIZE = 32        // number of samples per window
)(
    input  logic                    clk,
    input  logic                    rst_n,

    // Streaming input
    input  logic                    in_valid,
    input  logic [DATA_W-1:0]       in_sample,

    // Window output
    output logic                    window_valid,
    output logic [DATA_W-1:0]       window [0:WINDOW_SIZE-1]
);

    // ----------------------------
    // Internal storage
    // ----------------------------
    logic [DATA_W-1:0] buffer [0:WINDOW_SIZE-1];

    logic [$clog2(WINDOW_SIZE)-1:0]     wr_ptr;
    logic [$clog2(WINDOW_SIZE+1)-1:0]   sample_count;

    // ----------------------------
    // Write incoming samples
    // ----------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr        <= '0;
            sample_count  <= '0;
        end
        else if (in_valid) begin
            buffer[wr_ptr] <= in_sample;

            // Advance circular pointer
            wr_ptr <= (wr_ptr == WINDOW_SIZE-1) ? '0 : wr_ptr + 1'b1;

            // Count until window full
            if (sample_count < WINDOW_SIZE)
                sample_count <= sample_count + 1'b1;
        end
    end

    // ----------------------------
    // Window valid signal
    // ----------------------------
    assign window_valid = (sample_count == WINDOW_SIZE);

    // ----------------------------
    // Output window (oldest → newest) WITHOUT modulo
    // idx = wr_ptr + i (wrap if >= WINDOW_SIZE)
    // ----------------------------
    genvar i;
    generate
        for (i = 0; i < WINDOW_SIZE; i++) begin : WINDOW_OUT
            // Use an extra bit to safely hold (wr_ptr + i)
            logic [$clog2(WINDOW_SIZE):0] sum;
            logic [$clog2(WINDOW_SIZE)-1:0] idx;

            assign sum = wr_ptr + i;
            assign idx = (sum >= WINDOW_SIZE) ? (sum - WINDOW_SIZE) : sum[$clog2(WINDOW_SIZE)-1:0];

            assign window[i] = buffer[idx];
        end
    endgenerate

endmodule
