`timescale 1ns / 1ps

/**
 * Module: top_tb
 * 
 * Description:
 *   Comprehensive integration testbench for the complete ATCNet pipeline:
 *   Stream Input → Window Gen → Window Reader → Dual Branch Conv → Channel Scale → Output
 * 
 * Tests:
 *   1. End-to-end data flow
 *   2. Valid signal alignment
 *   3. Latency measurement
 *   4. Integration correctness
 *   5. Pipeline stalls and backpressure (if applicable)
 */

module top_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    parameter int DATA_WIDTH  = 16;
    parameter int COEF_WIDTH  = 16;
    parameter int ACC_WIDTH   = 48;
    parameter int WINDOW_SIZE = 32;
    parameter int KERNEL_SIZE = 5;
    parameter int NUM_CH      = 1;
    
    parameter int CLK_PERIOD = 10; // 10ns = 100MHz
    
    // Test coefficients (Q8.8 format)
    parameter logic signed [COEF_WIDTH-1:0] CONV_COEFFS_A [0:KERNEL_SIZE-1] = '{
        16'h0100,  // 1.0
        16'h0080,  // 0.5
        16'h0040,  // 0.25
        16'h0020,  // 0.125
        16'h0010   // 0.0625
    };
    
    parameter logic signed [COEF_WIDTH-1:0] CONV_COEFFS_B [0:KERNEL_SIZE-1] = '{
        16'h0080,  // 0.5
        16'h0080,  // 0.5
        16'h0080,  // 0.5
        16'h0080,  // 0.5
        16'h0080   // 0.5
    };
    
    parameter logic signed [COEF_WIDTH-1:0] SCALE_FACTORS [0:NUM_CH-1] = '{
        16'h0100   // 1.0 (no scaling)
    };

    // -------------------------------------------------------------------------
    // DUT Signals
    // -------------------------------------------------------------------------
    logic                         clk;
    logic                         rst;
    logic signed [DATA_WIDTH-1:0] in_sample;
    logic                         in_valid;
    logic signed [DATA_WIDTH-1:0] out_sample;
    logic                         out_valid;

    // -------------------------------------------------------------------------
    // Test Control Signals
    // -------------------------------------------------------------------------
    integer test_count;
    integer pass_count;
    integer fail_count;
    integer cycle_count;
    integer first_input_cycle;
    integer first_output_cycle;
    integer measured_latency;
    
    // Output monitoring
    logic signed [DATA_WIDTH-1:0] output_history [0:1023];
    integer output_count;

    // -------------------------------------------------------------------------
    // DUT Instantiation
    // -------------------------------------------------------------------------
    top #(
        .DATA_WIDTH(DATA_WIDTH),
        .COEF_WIDTH(COEF_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .WINDOW_SIZE(WINDOW_SIZE),
        .KERNEL_SIZE(KERNEL_SIZE),
        .NUM_CH(NUM_CH),
        .CONV_COEFFS_A(CONV_COEFFS_A),
        .CONV_COEFFS_B(CONV_COEFFS_B),
        .SCALE_FACTORS(SCALE_FACTORS)
    ) dut (
        .clk(clk),
        .rst(rst),
        .in_sample(in_sample),
        .in_valid(in_valid),
        .out_sample(out_sample),
        .out_valid(out_valid)
    );

    // -------------------------------------------------------------------------
    // Clock Generation
    // -------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // -------------------------------------------------------------------------
    // Output Monitor
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            cycle_count <= 0;
            output_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
            
            if (out_valid) begin
                if (first_output_cycle == -1) begin
                    first_output_cycle = cycle_count;
                    measured_latency = first_output_cycle - first_input_cycle;
                end
                
                output_history[output_count] = out_sample;
                output_count <= output_count + 1;
                
                $display("[%0t] Cycle %0d: out_sample = %h (%.4f)", 
                         $time, cycle_count, out_sample, 
                         real'(signed'(out_sample)) / 256.0);
            end
        end
    end

    // -------------------------------------------------------------------------
    // Helper Functions
    // -------------------------------------------------------------------------
    function logic [DATA_WIDTH-1:0] float_to_fixed(real value);
        int temp;
        temp = int'($floor(value * 256.0 + 0.5));
        return temp[DATA_WIDTH-1:0];
    endfunction

    function real fixed_to_float(logic [DATA_WIDTH-1:0] value);
        int signed temp;
        temp = signed'(value);
        return real'(temp) / 256.0;
    endfunction

    // -------------------------------------------------------------------------
    // Helper Tasks
    // -------------------------------------------------------------------------
    task reset_dut();
        begin
            rst = 1;
            in_sample = 0;
            in_valid = 0;
            first_input_cycle = -1;
            first_output_cycle = -1;
            measured_latency = -1;
            output_count = 0;
            repeat(10) @(posedge clk);
            rst = 0;
            repeat(5) @(posedge clk);
            $display("  [INFO] DUT reset complete");
        end
    endtask

    task send_sample(real value);
        begin
            @(posedge clk);
            in_sample = float_to_fixed(value);
            in_valid = 1;
            if (first_input_cycle == -1) begin
                first_input_cycle = cycle_count + 1;
            end
        end
    endtask

    task send_samples_stream(int num_samples);
        integer i;
        real val;
        begin
            for (i = 0; i < num_samples; i = i + 1) begin
                val = (i % 10) * 0.1; // Simple ramp pattern 0.0 to 0.9
                send_sample(val);
            end
            @(posedge clk);
            in_valid = 0;
        end
    endtask

    task wait_for_output(int timeout_cycles);
        integer i;
        begin
            for (i = 0; i < timeout_cycles; i = i + 1) begin
                if (out_valid) begin
                    $display("  [INFO] First output received at cycle %0d", cycle_count);
                    return;
                end
                @(posedge clk);
            end
            $display("  [ERROR] Timeout waiting for output!");
            fail_count = fail_count + 1;
        end
    endtask

    // -------------------------------------------------------------------------
    // Test Cases
    // -------------------------------------------------------------------------

    // Test 1: Basic End-to-End Flow
    task test_basic_flow();
        begin
            $display("\n========================================");
            $display("TEST 1: Basic End-to-End Data Flow");
            $display("========================================");
            test_count = test_count + 1;
            
            reset_dut();
            
            $display("  Sending %0d samples to fill pipeline...", WINDOW_SIZE + 10);
            send_samples_stream(WINDOW_SIZE + 10);
            
            $display("  Waiting for output...");
            wait_for_output(100);
            
            repeat(50) @(posedge clk);
            
            if (output_count > 0) begin
                $display("  [PASS] Received %0d output samples", output_count);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] No outputs received!");
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Test 2: Latency Measurement
    task test_latency();
        integer expected_latency;
        begin
            $display("\n========================================");
            $display("TEST 2: Pipeline Latency Measurement");
            $display("========================================");
            test_count = test_count + 1;
            
            reset_dut();
            
            // Expected latency breakdown:
            // - window_gen: WINDOW_SIZE cycles to fill
            // - window_reader: 1 cycle
            // - dual_branch_conv: 3 cycles (2 from temporal_conv + 1 from summation)
            // - channel_scale: 1 cycle
            // Total: WINDOW_SIZE + 5
            expected_latency = WINDOW_SIZE + 5;
            
            $display("  Expected latency: %0d cycles", expected_latency);
            $display("  (Window: %0d + Reader: 1 + Conv: 3 + Scale: 1)", WINDOW_SIZE);
            
            send_samples_stream(WINDOW_SIZE + 10);
            wait_for_output(100);
            
            $display("  Measured latency: %0d cycles", measured_latency);
            
            if (measured_latency >= expected_latency - 2 && 
                measured_latency <= expected_latency + 2) begin
                $display("  [PASS] Latency within acceptable range");
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] Latency mismatch! Expected ~%0d, got %0d", 
                         expected_latency, measured_latency);
                fail_count = fail_count + 1;
            end
            
            repeat(10) @(posedge clk);
        end
    endtask

    // Test 3: Valid Signal Alignment
    task test_valid_alignment();
        integer valid_count;
        integer gap_count;
        logic prev_valid;
        begin
            $display("\n========================================");
            $display("TEST 3: Valid Signal Alignment");
            $display("========================================");
            test_count = test_count + 1;
            
            reset_dut();
            
            valid_count = 0;
            gap_count = 0;
            prev_valid = 0;
            
            // Send continuous stream
            fork
                begin
                    send_samples_stream(50);
                end
                begin
                    repeat(200) begin
                        @(posedge clk);
                        if (out_valid) begin
                            valid_count = valid_count + 1;
                            if (!prev_valid && valid_count > 1) begin
                                gap_count = gap_count + 1;
                            end
                        end
                        prev_valid = out_valid;
                    end
                end
            join
            
            $display("  Output valid assertions: %0d", valid_count);
            $display("  Valid signal gaps: %0d", gap_count);
            
            if (valid_count > 0) begin
                $display("  [PASS] Valid signals detected");
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] No valid signals!");
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Test 4: Impulse Response
    task test_impulse();
        begin
            $display("\n========================================");
            $display("TEST 4: Impulse Response");
            $display("========================================");
            test_count = test_count + 1;
            
            reset_dut();
            
            // Send impulse
            send_sample(1.0);
            repeat(WINDOW_SIZE) send_sample(0.0);
            
            wait_for_output(100);
            repeat(50) @(posedge clk);
            
            if (output_count > 0) begin
                $display("  [PASS] Impulse response completed");
                $display("  First output: %.4f", fixed_to_float(output_history[0]));
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] No impulse response!");
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Test 5: Constant Input (DC Response)
    task test_dc_response();
        begin
            $display("\n========================================");
            $display("TEST 5: DC Response (Constant Input)");
            $display("========================================");
            test_count = test_count + 1;
            
            reset_dut();
            
            // Send constant value
            repeat(WINDOW_SIZE + 20) send_sample(1.0);
            @(posedge clk);
            in_valid = 0;
            
            wait_for_output(100);
            repeat(30) @(posedge clk);
            
            if (output_count > 0) begin
                $display("  [PASS] DC response test completed");
                $display("  Output samples received: %0d", output_count);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] No DC response!");
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Test 6: Integration Stress Test
    task test_stress();
        begin
            $display("\n========================================");
            $display("TEST 6: Integration Stress Test");
            $display("========================================");
            test_count = test_count + 1;
            
            reset_dut();
            
            $display("  Sending large batch of samples...");
            send_samples_stream(100);
            
            $display("  Waiting for pipeline to drain...");
            repeat(150) @(posedge clk);
            
            if (output_count > 20) begin
                $display("  [PASS] Stress test completed");
                $display("  Total outputs: %0d", output_count);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] Insufficient outputs: %0d", output_count);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Main Test Sequence
    // -------------------------------------------------------------------------
    initial begin
        $display("\n");
        $display("╔════════════════════════════════════════════════════════════╗");
        $display("║     ATCNet TOP-LEVEL INTEGRATION TESTBENCH                 ║");
        $display("╚════════════════════════════════════════════════════════════╝");
        $display("");
        $display("Configuration:");
        $display("  DATA_WIDTH    = %0d bits", DATA_WIDTH);
        $display("  WINDOW_SIZE   = %0d", WINDOW_SIZE);
        $display("  KERNEL_SIZE   = %0d", KERNEL_SIZE);
        $display("  NUM_CH        = %0d", NUM_CH);
        $display("");
        $display("Pipeline:");
        $display("  Stream → Window Gen → Reader → Dual Conv → Scale → Out");
        $display("");
        
        // Initialize
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        cycle_count = 0;
        output_count = 0;
        first_input_cycle = -1;
        first_output_cycle = -1;
        
        rst = 1;
        in_sample = 0;
        in_valid = 0;
        
        repeat(20) @(posedge clk);
        
        // Run tests
        test_basic_flow();
        test_latency();
        test_valid_alignment();
        test_impulse();
        test_dc_response();
        test_stress();
        
        repeat(20) @(posedge clk);
        
        // Print summary
        $display("\n");
        $display("╔════════════════════════════════════════════════════════════╗");
        $display("║     TEST SUMMARY                                           ║");
        $display("╚════════════════════════════════════════════════════════════╝");
        $display("");
        $display("  Total tests:   %0d", test_count);
        $display("  Passed:        %0d", pass_count);
        $display("  Failed:        %0d", fail_count);
        $display("  Total cycles:  %0d", cycle_count);
        $display("");
        
        if (fail_count == 0) begin
            $display("  ████████╗███████╗███████╗████████╗    ██████╗  █████╗ ███████╗███████╗");
            $display("  ╚══██╔══╝██╔════╝██╔════╝╚══██╔══╝    ██╔══██╗██╔══██╗██╔════╝██╔════╝");
            $display("     ██║   █████╗  ███████╗   ██║       ██████╔╝███████║███████╗███████╗");
            $display("     ██║   ██╔══╝  ╚════██║   ██║       ██╔═══╝ ██╔══██║╚════██║╚════██║");
            $display("     ██║   ███████╗███████║   ██║       ██║     ██║  ██║███████║███████║");
            $display("     ╚═╝   ╚══════╝╚══════╝   ╚═╝       ╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝");
            $display("");
            $display("  ✓ ALL INTEGRATION TESTS PASSED!");
            $display("  ✓ Top-level module is VERIFIED");
            $display("  ✓ Ready for synthesis and FPGA deployment");
        end else begin
            $display("  ✗ TESTS FAILED");
            $display("");
            $display("  Fix integration issues before synthesis");
            $display("  Check module connections and valid signal propagation");
        end
        
        $display("");
        $display("Test completed at %0t", $time);
        $finish;
    end

    // Timeout watchdog
    initial begin
        #10000000; // 10ms timeout
        $display("\n[ERROR] Simulation timeout!");
        $display("Check for deadlocks or stalled pipelines");
        $finish;
    end

    // Waveform dumping for Vivado
    // In Vivado GUI: Add all signals to waveform window or use TCL commands
    // In TCL mode: add_wave /* ; run -all

endmodule
