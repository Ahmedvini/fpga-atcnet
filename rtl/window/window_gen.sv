module window_gen #(
    parameter int DATA_W = 16,
    parameter int WINDOW_SIZE = 32
)(
    input  logic                    clk,
    input  logic                    rst,
    input  logic                    in_valid,
    input  logic [DATA_W-1:0]       in_sample,
    output logic                    window_valid,
    // ADDED 'signed' HERE
    output logic signed [DATA_W-1:0] window [0:WINDOW_SIZE-1]
);

    logic [DATA_W-1:0] buffer [0:WINDOW_SIZE-1];
    logic [$clog2(WINDOW_SIZE)-1:0]   wr_ptr;
    logic [$clog2(WINDOW_SIZE+1)-1:0] sample_count;

    always_ff @(posedge clk) begin
        if (rst) begin
            wr_ptr       <= '0;
            sample_count <= '0;
        end
        else if (in_valid) begin
            buffer[wr_ptr] <= in_sample;
            wr_ptr <= (wr_ptr == WINDOW_SIZE-1) ? '0 : wr_ptr + 1'b1;
            if (sample_count < WINDOW_SIZE)
                sample_count <= sample_count + 1'b1;
        end
    end

    assign window_valid = (in_valid && (sample_count == WINDOW_SIZE));

    genvar i;
    generate
        for (i = 0; i < WINDOW_SIZE; i++) begin : WINDOW_OUT
            logic [$clog2(WINDOW_SIZE):0] sum;
            logic [$clog2(WINDOW_SIZE)-1:0] idx;

            assign sum = wr_ptr + i;
            assign idx = (sum >= WINDOW_SIZE) ? (sum - WINDOW_SIZE) : sum[$clog2(WINDOW_SIZE)-1:0];
            assign window[i] = buffer[idx];
        end
    endgenerate

endmodule