/**
 * Module: integrated_example
 * 
 * Description:
 *   Example showing how to integrate window_gen and temporal_conv modules
 *   for processing streaming data through a sliding window and FIR filter.
 * 
 * Data Flow:
 *   Raw Stream → Window Generator → Temporal Convolution → Filtered Output
 * 
 * Owner: Person 3 (integration example)
 */

`timescale 1ns / 1ps

module integrated_example #(
    parameter int DATA_WIDTH = 16,
    parameter int WINDOW_SIZE = 32,
    parameter int KERNEL_SIZE = 5
)(
    input  logic clk,
    input  logic rst_n,          // Active LOW reset for top-level
    
    // Streaming input
    input  logic stream_valid,
    input  logic signed [DATA_WIDTH-1:0] stream_data,
    
    // Processed output
    output logic output_valid,
    output logic signed [DATA_WIDTH-1:0] output_data
);

    //==========================================================================
    // Internal Signals
    //==========================================================================
    
    // Window generator outputs
    logic window_valid;
    logic [DATA_WIDTH-1:0] window_data [0:WINDOW_SIZE-1];
    
    // Temporal convolution signals
    logic conv_valid;
    logic signed [DATA_WIDTH-1:0] conv_input;
    logic conv_output_valid;
    logic signed [DATA_WIDTH-1:0] conv_output;
    
    // Control logic
    logic [$clog2(WINDOW_SIZE)-1:0] window_idx;
    logic processing_window;
    
    // FIR filter coefficients (example: simple averaging filter)
    logic signed [DATA_WIDTH-1:0] fir_coeffs [KERNEL_SIZE];
    initial begin
        // Simple averaging: each coefficient = 1/KERNEL_SIZE
        // For KERNEL_SIZE=5: 1/5 = 0.2 = 0x0033 in Q8.8
        fir_coeffs[0] = 16'h0033;  // 0.2
        fir_coeffs[1] = 16'h0033;  // 0.2
        fir_coeffs[2] = 16'h0033;  // 0.2
        fir_coeffs[3] = 16'h0033;  // 0.2
        fir_coeffs[4] = 16'h0033;  // 0.2
    end
    
    //==========================================================================
    // Module 1: Window Generator
    //==========================================================================
    
    window_gen #(
        .DATA_W(DATA_WIDTH),
        .WINDOW_SIZE(WINDOW_SIZE)
    ) u_window (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(stream_valid),
        .in_sample(stream_data),
        .window_valid(window_valid),
        .window(window_data)
    );
    
    //==========================================================================
    // Module 2: Temporal Convolution (FIR Filter)
    //==========================================================================
    
    temporal_conv #(
        .DATA_WIDTH(DATA_WIDTH),
        .COEF_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(48),
        .KERNEL_SIZE(KERNEL_SIZE),
        .COEFFS(fir_coeffs)
    ) u_conv (
        .clk(clk),
        .rst(~rst_n),              // NOTE: opposite polarity!
        .x_in(conv_input),
        .x_valid(conv_valid),
        .y_out(conv_output),
        .y_valid(conv_output_valid)
    );
    
    //==========================================================================
    // Processing Control Logic
    //==========================================================================
    
    // Strategy: When window is full, feed all samples through FIR filter
    // This processes each window sample by sample
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            window_idx <= '0;
            processing_window <= 1'b0;
            conv_input <= '0;
            conv_valid <= 1'b0;
        end else begin
            // Default: no valid data
            conv_valid <= 1'b0;
            
            // Start processing when window becomes valid
            if (window_valid && !processing_window) begin
                processing_window <= 1'b1;
                window_idx <= '0;
            end
            
            // Feed samples to convolution
            if (processing_window) begin
                conv_input <= window_data[window_idx];
                conv_valid <= 1'b1;
                
                // Advance to next sample
                if (window_idx < WINDOW_SIZE - 1) begin
                    window_idx <= window_idx + 1'b1;
                end else begin
                    // Finished processing this window
                    processing_window <= 1'b0;
                    window_idx <= '0;
                end
            end
        end
    end
    
    // Output assignment
    assign output_data = conv_output;
    assign output_valid = conv_output_valid;
    
    //==========================================================================
    // Debug: Monitor window updates (can be removed for synthesis)
    //==========================================================================
    
    always_ff @(posedge clk) begin
        if (window_valid && !processing_window) begin
            $display("[%0t] New window ready - starting processing", $time);
        end
        
        if (conv_output_valid) begin
            $display("[%0t] FIR output: %h (%.4f)", $time, conv_output, 
                     real'(signed'(conv_output)) / 256.0);
        end
    end

endmodule

/**
 * ============================================================================
 * USAGE NOTES
 * ============================================================================
 * 
 * 1. Reset Polarity:
 *    - Top-level uses rst_n (active LOW) like window_gen
 *    - Internally inverts to rst (active HIGH) for temporal_conv
 * 
 * 2. Processing Flow:
 *    a) Stream data arrives → window_gen accumulates
 *    b) When WINDOW_SIZE samples collected → window_valid goes high
 *    c) Control logic feeds each window sample through FIR filter
 *    d) Filtered outputs appear on output_data/output_valid
 * 
 * 3. Timing:
 *    - Window fill time: WINDOW_SIZE cycles (if stream_valid always high)
 *    - Processing time: WINDOW_SIZE cycles to push through FIR
 *    - FIR latency: 2 cycles per sample
 *    - Total latency: ~WINDOW_SIZE + 2 cycles
 * 
 * 4. Coefficient Format:
 *    - Q8.8 fixed-point: 8 integer bits, 8 fractional bits
 *    - Example: 0x0100 = 1.0, 0x0080 = 0.5, 0x0040 = 0.25
 *    - Value = coefficient / 256.0
 * 
 * 5. Alternative Processing Strategies:
 * 
 *    Option A (Current): Process entire window sequentially
 *      + Simple control logic
 *      - Processes samples one by one
 * 
 *    Option B: Process only center/latest sample per window
 *      conv_input <= window_data[WINDOW_SIZE-1];  // Latest sample
 *      + Faster processing
 *      - May not need full window
 * 
 *    Option C: Parallel processing with multiple FIR filters
 *      + Highest throughput
 *      - More hardware resources
 * 
 * 6. Example Instantiation:
 * 
 *    integrated_example #(
 *        .DATA_WIDTH(16),
 *        .WINDOW_SIZE(32),
 *        .KERNEL_SIZE(5)
 *    ) u_processor (
 *        .clk(clk),
 *        .rst_n(rst_n),
 *        .stream_valid(adc_valid),
 *        .stream_data(adc_data),
 *        .output_valid(dac_valid),
 *        .output_data(dac_data)
 *    );
 * 
 * ============================================================================
 */
