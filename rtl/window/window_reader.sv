module window_reader #(
    parameter int DATA_WIDTH = 16,
    parameter int WINDOW_SIZE = 32
) (
    input  logic clk,
    input  logic rst,
    // This input is already signed and unpacked
    input  logic signed [DATA_WIDTH-1:0] window_in [0:WINDOW_SIZE-1],
    input  logic                         window_valid,

    output logic signed [DATA_WIDTH-1:0] stream_out,
    output logic                         stream_valid
);

    always_ff @(posedge clk) begin
        if (rst) begin
            stream_out   <= '0;
            stream_valid <= 1'b0;
        end else begin
            stream_valid <= window_valid;
            if (window_valid) begin
                // Selects newest sample
                stream_out <= window_in[WINDOW_SIZE-1];
            end
        end
    end

endmodule