/**
 * Module: window_reader
 * 
 * Description:
 *   Bridge module that adapts the parallel output of 'window_gen' to a
 *   scalar streaming interface needed by temporal convolution blocks.
 *   
 *   It simply selects the newest sample from the window (which drives the convolution stream)
 *   and registers it to provide a clean timing boundary.
 * 
 * Latency:
 *   1 cycle (Registered output).
 */

module window_reader #(
    parameter int DATA_WIDTH = 16,
    parameter int WINDOW_SIZE = 32
) (
    input  logic clk,
    input  logic rst,

    // Window Input
    input  logic signed [DATA_WIDTH-1:0] window_in [0:WINDOW_SIZE-1],
    input  logic                         window_valid,

    // Streaming Output
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
                // Select the newest sample (last element) to feed the stream
                stream_out <= window_in[WINDOW_SIZE-1];
            end
        end
    end

endmodule
