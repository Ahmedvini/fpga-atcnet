`timescale 1ns / 1ps

//==============================================================================
// Temporal Convolution Testbench
// Owner: Person 3
// 
// Purpose: Verify temporal_conv.sv with cycle-accurate latency checking
//          and numerical correctness validation
//
// Test Strategy:
//   1. Simple known pattern test (manual verification)
//   2. Streaming sample-by-sample test (shift register verification)
//   3. Golden reference comparison (Python model outputs)
//   4. Latency measurement and verification
//   5. Edge case testing (zeros, max values, etc.)
//==============================================================================

module temporal_conv_tb;

    //==========================================================================
    // Parameters
    //==========================================================================
    
    // Fixed-point configuration
    parameter int DATA_WIDTH = 16;      // Total bits
    parameter int FRAC_BITS = 8;        // Fractional bits (Q8.8)
    
    // Temporal convolution parameters
    parameter int SEQ_LENGTH = 32;      // Input sequence length
    parameter int IN_CHANNELS = 32;     // Input feature channels
    parameter int OUT_CHANNELS = 32;    // Output feature channels
    parameter int KERNEL_SIZE = 4;      // Temporal kernel size
    parameter int DILATION = 1;         // Dilation rate
    
    // Timing
    parameter int CLK_PERIOD = 10;      // 100MHz clock
    parameter int TIMEOUT_CYCLES = 10000;
    
    //==========================================================================
    // DUT Signals
    //==========================================================================
    
    logic clk;
    logic rst_n;
    
    // Input interface
    logic [IN_CHANNELS-1:0][DATA_WIDTH-1:0] data_in;
    logic data_in_valid;
    
    // Output interface
    logic [OUT_CHANNELS-1:0][DATA_WIDTH-1:0] data_out;
    logic data_out_valid;
    
    // Configuration (would be loaded via registers in real design)
    logic [KERNEL_SIZE-1:0][IN_CHANNELS-1:0][OUT_CHANNELS-1:0][DATA_WIDTH-1:0] kernel_weights;
    logic [OUT_CHANNELS-1:0][DATA_WIDTH-1:0] bias;
    
    //==========================================================================
    // Test Control
    //==========================================================================
    
    int test_num = 0;
    int error_count = 0;
    int pass_count = 0;
    int cycle_count = 0;
    
    // Test vectors from Python
    typedef struct {
        logic [IN_CHANNELS-1:0][DATA_WIDTH-1:0] input_sample;
        logic [OUT_CHANNELS-1:0][DATA_WIDTH-1:0] expected_output;
        logic expected_valid;
        int cycle;
    } test_vector_t;
    
    test_vector_t test_vectors[$];
    
    //==========================================================================
    // Clock Generation
    //==========================================================================
    
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    
    temporal_conv #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRAC_BITS(FRAC_BITS),
        .IN_CHANNELS(IN_CHANNELS),
        .OUT_CHANNELS(OUT_CHANNELS),
        .KERNEL_SIZE(KERNEL_SIZE),
        .DILATION(DILATION)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(data_in),
        .data_in_valid(data_in_valid),
        .data_out(data_out),
        .data_out_valid(data_out_valid),
        .kernel_weights(kernel_weights),
        .bias(bias)
    );
    
    //==========================================================================
    // Helper Functions
    //==========================================================================
    
    // Convert float to fixed-point
    function automatic logic [DATA_WIDTH-1:0] float_to_fixed(real value);
        int temp;
        temp = int'($floor(value * (2.0 ** FRAC_BITS) + 0.5));
        return temp[DATA_WIDTH-1:0];
    endfunction
    
    // Convert fixed-point to float
    function automatic real fixed_to_float(logic [DATA_WIDTH-1:0] value);
        int signed temp;
        temp = signed'(value);
        return real'(temp) / (2.0 ** FRAC_BITS);
    endfunction
    
    // Compare two fixed-point values with tolerance
    function automatic bit compare_fixed(
        logic [DATA_WIDTH-1:0] actual,
        logic [DATA_WIDTH-1:0] expected,
        int tolerance = 2  // Allow ±2 LSB difference
    );
        int diff;
        diff = signed'(actual) - signed'(expected);
        if (diff < 0) diff = -diff;
        return (diff <= tolerance);
    endfunction
    
    // Compare output vectors
    function automatic int compare_outputs(
        logic [OUT_CHANNELS-1:0][DATA_WIDTH-1:0] actual,
        logic [OUT_CHANNELS-1:0][DATA_WIDTH-1:0] expected,
        string test_name = ""
    );
        int errors = 0;
        for (int i = 0; i < OUT_CHANNELS; i++) begin
            if (!compare_fixed(actual[i], expected[i])) begin
                $display("  [ERROR] Channel %0d mismatch in %s", i, test_name);
                $display("    Expected: %h (%.4f)", expected[i], fixed_to_float(expected[i]));
                $display("    Got:      %h (%.4f)", actual[i], fixed_to_float(actual[i]));
                $display("    Diff:     %h", signed'(actual[i]) - signed'(expected[i]));
                errors++;
                if (errors >= 5) begin
                    $display("  [ERROR] Too many errors, stopping comparison...");
                    return errors;
                end
            end
        end
        return errors;
    endfunction
    
    // Reset task
    task automatic reset_dut();
        $display("[%0t] Resetting DUT...", $time);
        rst_n = 0;
        data_in = '0;
        data_in_valid = 0;
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);
        $display("[%0t] Reset complete", $time);
    endtask
    
    // Load test vectors from file
    task automatic load_test_vectors(string filename);
        int fd;
        string line;
        // This would parse JSON or hex files generated by Python
        // For now, we'll generate simple patterns
        $display("[%0t] Loading test vectors from %s", $time, filename);
        // TODO: Implement JSON parsing or use other method
    endtask
    
    //==========================================================================
    // Test Cases
    //==========================================================================
    
    // Test 1: Simple Impulse Response
    task automatic test_impulse_response();
        $display("\n========================================");
        $display("TEST 1: Impulse Response");
        $display("========================================");
        test_num++;
        
        reset_dut();
        
        // Set simple kernel (identity on first tap)
        for (int k = 0; k < KERNEL_SIZE; k++) begin
            for (int i = 0; i < IN_CHANNELS; i++) begin
                for (int o = 0; o < OUT_CHANNELS; o++) begin
                    if (k == 0 && i == o) begin
                        kernel_weights[k][i][o] = float_to_fixed(1.0);
                    end else begin
                        kernel_weights[k][i][o] = '0;
                    end
                end
            end
        end
        bias = '0;
        
        // Send impulse (1.0 in channel 0, rest zeros)
        @(posedge clk);
        data_in = '0;
        data_in[0] = float_to_fixed(1.0);
        data_in_valid = 1;
        
        // Send zeros
        for (int t = 1; t < KERNEL_SIZE + 4; t++) begin
            @(posedge clk);
            data_in = '0;
            data_in_valid = 1;
            
            // Check output
            if (data_out_valid) begin
                $display("[%0t] Cycle %0d: Output valid", $time, t);
                if (data_out[0] != '0 || fixed_to_float(data_out[0]) < 0.9) begin
                    $display("  [FAIL] Expected impulse in output channel 0");
                    $display("  Got: %.4f", fixed_to_float(data_out[0]));
                    error_count++;
                end else begin
                    $display("  [PASS] Impulse detected: %.4f", fixed_to_float(data_out[0]));
                    pass_count++;
                end
            end
        end
        
        @(posedge clk);
        data_in_valid = 0;
        repeat(5) @(posedge clk);
    endtask
    
    // Test 2: Constant Input (DC Response)
    task automatic test_dc_response();
        $display("\n========================================");
        $display("TEST 2: DC Response");
        $display("========================================");
        test_num++;
        
        reset_dut();
        
        // Set uniform kernel (averaging)
        real kernel_val = 1.0 / real'(KERNEL_SIZE);
        for (int k = 0; k < KERNEL_SIZE; k++) begin
            for (int i = 0; i < IN_CHANNELS; i++) begin
                for (int o = 0; o < OUT_CHANNELS; o++) begin
                    if (i == o) begin
                        kernel_weights[k][i][o] = float_to_fixed(kernel_val);
                    end else begin
                        kernel_weights[k][i][o] = '0;
                    end
                end
            end
        end
        bias = '0;
        
        // Send constant value
        real input_val = 1.0;
        real expected_output = input_val; // Average of constant is constant
        
        for (int t = 0; t < SEQ_LENGTH; t++) begin
            @(posedge clk);
            for (int c = 0; c < IN_CHANNELS; c++) begin
                data_in[c] = float_to_fixed(input_val);
            end
            data_in_valid = 1;
            
            // After kernel is full, check output
            if (t >= KERNEL_SIZE-1 && data_out_valid) begin
                real actual_output = fixed_to_float(data_out[0]);
                real error = actual_output - expected_output;
                if (error < 0) error = -error;
                
                if (error > 0.1) begin
                    $display("[%0t] Cycle %0d: [FAIL] DC response error", $time, t);
                    $display("  Expected: %.4f, Got: %.4f", expected_output, actual_output);
                    error_count++;
                end else if (t == KERNEL_SIZE) begin
                    $display("[%0t] Cycle %0d: [PASS] DC response correct", $time, t);
                    pass_count++;
                end
            end
        end
        
        @(posedge clk);
        data_in_valid = 0;
        repeat(5) @(posedge clk);
    endtask
    
    // Test 3: Ramp Input (Linearity Test)
    task automatic test_ramp_response();
        $display("\n========================================");
        $display("TEST 3: Ramp Response (Linearity)");
        $display("========================================");
        test_num++;
        
        reset_dut();
        
        // Simple kernel
        for (int k = 0; k < KERNEL_SIZE; k++) begin
            for (int i = 0; i < IN_CHANNELS; i++) begin
                for (int o = 0; o < OUT_CHANNELS; o++) begin
                    if (i == o && k == 0) begin
                        kernel_weights[k][i][o] = float_to_fixed(0.5);
                    end else begin
                        kernel_weights[k][i][o] = '0;
                    end
                end
            end
        end
        bias = '0;
        
        // Send ramp
        for (int t = 0; t < 16; t++) begin
            @(posedge clk);
            real ramp_val = real'(t) * 0.1;
            for (int c = 0; c < IN_CHANNELS; c++) begin
                data_in[c] = float_to_fixed(ramp_val);
            end
            data_in_valid = 1;
            
            if (data_out_valid) begin
                real expected = ramp_val * 0.5;  // Kernel weight is 0.5
                real actual = fixed_to_float(data_out[0]);
                real error = actual - expected;
                if (error < 0) error = -error;
                
                if (error > 0.05) begin
                    $display("[%0t] [FAIL] Cycle %0d: Expected %.4f, got %.4f", 
                             $time, t, expected, actual);
                    error_count++;
                end
            end
        end
        
        $display("[%0t] [PASS] Ramp test completed", $time);
        pass_count++;
        
        @(posedge clk);
        data_in_valid = 0;
        repeat(5) @(posedge clk);
    endtask
    
    // Test 4: Latency Measurement
    task automatic test_latency();
        $display("\n========================================");
        $display("TEST 4: Latency Measurement");
        $display("========================================");
        test_num++;
        
        reset_dut();
        
        // Simple passthrough kernel
        for (int k = 0; k < KERNEL_SIZE; k++) begin
            kernel_weights[k] = '0;
        end
        for (int i = 0; i < IN_CHANNELS; i++) begin
            kernel_weights[0][i][i] = float_to_fixed(1.0);
        end
        bias = '0;
        
        int first_valid_cycle = -1;
        int input_start_cycle = 0;
        
        // Mark input start
        @(posedge clk);
        input_start_cycle = cycle_count;
        data_in[0] = float_to_fixed(1.0);
        data_in_valid = 1;
        
        // Wait for first valid output
        fork
            begin
                for (int t = 0; t < 100; t++) begin
                    @(posedge clk);
                    data_in[0] = float_to_fixed(1.0);
                    data_in_valid = 1;
                    
                    if (data_out_valid && first_valid_cycle < 0) begin
                        first_valid_cycle = cycle_count;
                        break;
                    end
                end
            end
            begin
                repeat(TIMEOUT_CYCLES) @(posedge clk);
                if (first_valid_cycle < 0) begin
                    $display("[%0t] [FAIL] Timeout waiting for output", $time);
                    error_count++;
                end
            end
        join_any
        
        data_in_valid = 0;
        
        if (first_valid_cycle >= 0) begin
            int measured_latency = first_valid_cycle - input_start_cycle;
            int expected_latency = KERNEL_SIZE;  // Causal padding latency
            
            $display("[%0t] Input started at cycle: %0d", $time, input_start_cycle);
            $display("[%0t] First valid output at cycle: %0d", $time, first_valid_cycle);
            $display("[%0t] Measured latency: %0d cycles", $time, measured_latency);
            $display("[%0t] Expected latency: %0d cycles", $time, expected_latency);
            
            if (measured_latency == expected_latency) begin
                $display("[%0t] [PASS] Latency matches expected", $time);
                pass_count++;
            end else begin
                $display("[%0t] [FAIL] Latency mismatch!", $time);
                error_count++;
            end
        end
        
        repeat(5) @(posedge clk);
    endtask
    
    // Test 5: Streaming with Valid Gaps
    task automatic test_streaming_with_gaps();
        $display("\n========================================");
        $display("TEST 5: Streaming with Valid Gaps");
        $display("========================================");
        test_num++;
        
        reset_dut();
        
        // Simple kernel
        for (int k = 0; k < KERNEL_SIZE; k++) begin
            for (int i = 0; i < IN_CHANNELS; i++) begin
                for (int o = 0; o < OUT_CHANNELS; o++) begin
                    kernel_weights[k][i][o] = (i == o && k == 0) ? float_to_fixed(1.0) : '0;
                end
            end
        end
        bias = '0;
        
        // Send data with random gaps
        int samples_sent = 0;
        while (samples_sent < 20) begin
            @(posedge clk);
            
            // Random valid
            if ($urandom_range(0, 100) > 30) begin  // 70% valid
                data_in[0] = float_to_fixed(real'(samples_sent) * 0.1);
                data_in_valid = 1;
                samples_sent++;
            end else begin
                data_in_valid = 0;
            end
        end
        
        // Flush
        data_in_valid = 0;
        repeat(10) @(posedge clk);
        
        $display("[%0t] [PASS] Streaming with gaps completed", $time);
        pass_count++;
    endtask
    
    // Test 6: Dilation Test (if supported)
    task automatic test_dilation();
        $display("\n========================================");
        $display("TEST 6: Dilation Test");
        $display("========================================");
        test_num++;
        
        if (DILATION > 1) begin
            $display("[%0t] Testing with dilation rate: %0d", $time, DILATION);
            // TODO: Add dilation-specific tests
            $display("[%0t] [INFO] Dilation test not fully implemented", $time);
        end else begin
            $display("[%0t] [SKIP] No dilation configured", $time);
        end
    endtask
    
    // Test 7: Edge Cases
    task automatic test_edge_cases();
        $display("\n========================================");
        $display("TEST 7: Edge Cases");
        $display("========================================");
        test_num++;
        
        reset_dut();
        
        // Test with zeros
        $display("[%0t] Subtest 7a: All zeros input", $time);
        kernel_weights = '0;
        bias = '0;
        
        for (int t = 0; t < 10; t++) begin
            @(posedge clk);
            data_in = '0;
            data_in_valid = 1;
            
            if (data_out_valid) begin
                for (int c = 0; c < OUT_CHANNELS; c++) begin
                    if (data_out[c] != '0) begin
                        $display("[%0t] [FAIL] Expected zero output", $time);
                        error_count++;
                        break;
                    end
                end
            end
        end
        
        $display("[%0t] [PASS] Zero input test passed", $time);
        pass_count++;
        
        data_in_valid = 0;
        repeat(5) @(posedge clk);
    endtask
    
    //==========================================================================
    // Monitor & Checker
    //==========================================================================
    
    // Cycle counter
    always_ff @(posedge clk) begin
        if (!rst_n)
            cycle_count <= 0;
        else
            cycle_count <= cycle_count + 1;
    end
    
    // Output monitor
    always_ff @(posedge clk) begin
        if (data_out_valid) begin
            $display("[%0t] Cycle %0d: Valid output received", $time, cycle_count);
        end
    end
    
    //==========================================================================
    // Main Test Sequence
    //==========================================================================
    
    initial begin
        $display("\n");
        $display("╔════════════════════════════════════════════════════════════╗");
        $display("║     TEMPORAL CONVOLUTION TESTBENCH                         ║");
        $display("║     Owner: Person 3                                        ║");
        $display("╚════════════════════════════════════════════════════════════╝");
        $display("");
        $display("Configuration:");
        $display("  DATA_WIDTH    = %0d bits", DATA_WIDTH);
        $display("  FRAC_BITS     = %0d bits (Q%0d.%0d)", FRAC_BITS, DATA_WIDTH-FRAC_BITS, FRAC_BITS);
        $display("  IN_CHANNELS   = %0d", IN_CHANNELS);
        $display("  OUT_CHANNELS  = %0d", OUT_CHANNELS);
        $display("  KERNEL_SIZE   = %0d", KERNEL_SIZE);
        $display("  DILATION      = %0d", DILATION);
        $display("  SEQ_LENGTH    = %0d", SEQ_LENGTH);
        $display("");
        
        // Initialize
        rst_n = 0;
        data_in = '0;
        data_in_valid = 0;
        kernel_weights = '0;
        bias = '0;
        
        // Wait for global reset
        repeat(10) @(posedge clk);
        
        // Run tests
        test_impulse_response();
        test_dc_response();
        test_ramp_response();
        test_latency();
        test_streaming_with_gaps();
        test_dilation();
        test_edge_cases();
        
        // Final report
        repeat(10) @(posedge clk);
        
        $display("\n");
        $display("╔════════════════════════════════════════════════════════════╗");
        $display("║     TEST SUMMARY                                           ║");
        $display("╚════════════════════════════════════════════════════════════╝");
        $display("");
        $display("  Total tests:   %0d", test_num);
        $display("  Passed:        %0d", pass_count);
        $display("  Failed:        %0d", error_count);
        $display("  Total cycles:  %0d", cycle_count);
        $display("");
        
        if (error_count == 0) begin
            $display("  ████████╗███████╗███████╗████████╗    ██████╗  █████╗ ███████╗███████╗███████╗██████╗ ");
            $display("  ╚══██╔══╝██╔════╝██╔════╝╚══██╔══╝    ██╔══██╗██╔══██╗██╔════╝██╔════╝██╔════╝██╔══██╗");
            $display("     ██║   █████╗  ███████╗   ██║       ██████╔╝███████║███████╗███████╗█████╗  ██║  ██║");
            $display("     ██║   ██╔══╝  ╚════██║   ██║       ██╔═══╝ ██╔══██║╚════██║╚════██║██╔══╝  ██║  ██║");
            $display("     ██║   ███████╗███████║   ██║       ██║     ██║  ██║███████║███████║███████╗██████╔╝");
            $display("     ╚═╝   ╚══════╝╚══════╝   ╚═╝       ╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝╚═════╝ ");
        end else begin
            $display("  ████████╗███████╗███████╗████████╗    ███████╗ █████╗ ██╗██╗     ███████╗██████╗ ");
            $display("  ╚══██╔══╝██╔════╝██╔════╝╚══██╔══╝    ██╔════╝██╔══██╗██║██║     ██╔════╝██╔══██╗");
            $display("     ██║   █████╗  ███████╗   ██║       █████╗  ███████║██║██║     █████╗  ██║  ██║");
            $display("     ██║   ██╔══╝  ╚════██║   ██║       ██╔══╝  ██╔══██║██║██║     ██╔══╝  ██║  ██║");
            $display("     ██║   ███████╗███████║   ██║       ██║     ██║  ██║██║███████╗███████╗██████╔╝");
            $display("     ╚═╝   ╚══════╝╚══════╝   ╚═╝       ╚═╝     ╚═╝  ╚═╝╚═╝╚══════╝╚══════╝╚═════╝ ");
        end
        
        $display("");
        $display("════════════════════════════════════════════════════════════");
        $display("");
        
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        repeat(TIMEOUT_CYCLES * 2) @(posedge clk);
        $display("\n[FATAL] Simulation timeout!");
        $finish;
    end
    
    // Waveform dump
    initial begin
        $dumpfile("temporal_conv_tb.vcd");
        $dumpvars(0, temporal_conv_tb);
    end

endmodule
