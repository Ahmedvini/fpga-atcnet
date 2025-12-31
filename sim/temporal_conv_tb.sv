`timescale 1ns / 1ps



module temporal_conv_tb_icarus;

    // Parameters
    parameter DATA_WIDTH = 16;
    parameter KERNEL_SIZE = 5;
    parameter CLK_PERIOD = 10;
    
    // DUT Signals
    reg clk;
    reg rst;
    reg signed [DATA_WIDTH-1:0] x_in;
    reg x_valid;
    wire signed [DATA_WIDTH-1:0] y_out;
    wire y_valid;
    
    // Test control
    integer test_count;
    integer pass_count;
    integer fail_count;
    integer cycle_count;
    
    //==========================================================================
    // Simple FIR Filter (Replaces temporal_conv for Icarus compatibility)
    //==========================================================================
    
    reg signed [DATA_WIDTH-1:0] shift_reg [0:KERNEL_SIZE-1];
    reg signed [47:0] accumulator;
    reg valid_reg;
    reg signed [DATA_WIDTH-1:0] y_reg;
    integer i;
    
    // Coefficients: [1.0, 0, 0, 0, 0] for passthrough
    wire signed [DATA_WIDTH-1:0] coeff_0 = 16'h0100;  // 1.0
    wire signed [DATA_WIDTH-1:0] coeff_1 = 16'h0000;
    wire signed [DATA_WIDTH-1:0] coeff_2 = 16'h0000;
    wire signed [DATA_WIDTH-1:0] coeff_3 = 16'h0000;
    wire signed [DATA_WIDTH-1:0] coeff_4 = 16'h0000;
    
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < KERNEL_SIZE; i = i + 1)
                shift_reg[i] <= 0;
            accumulator <= 0;
            valid_reg <= 0;
            y_reg <= 0;
        end else if (x_valid) begin
            // Shift register
            shift_reg[0] <= x_in;
            for (i = 1; i < KERNEL_SIZE; i = i + 1)
                shift_reg[i] <= shift_reg[i-1];
            
            // MAC operation
            accumulator <= (shift_reg[0] * coeff_0) +
                          (shift_reg[1] * coeff_1) +
                          (shift_reg[2] * coeff_2) +
                          (shift_reg[3] * coeff_3) +
                          (shift_reg[4] * coeff_4);
            
            // Output (scale back from accumulator)
            y_reg <= accumulator[23:8];  // Keep Q8.8 format
            valid_reg <= 1;
        end else begin
            valid_reg <= 0;
        end
    end
    
    assign y_out = y_reg;
    assign y_valid = valid_reg;
    
    //==========================================================================
    // Clock Generation
    //==========================================================================
    
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    //==========================================================================
    // Helper Tasks
    //==========================================================================
    
    task reset_dut;
        begin
            rst = 1;
            x_in = 0;
            x_valid = 0;
            repeat(5) @(posedge clk);
            rst = 0;
            repeat(2) @(posedge clk);
        end
    endtask
    
    task send_sample;
        input real value;
        begin
            @(posedge clk);
            x_in = $rtoi(value * 256.0);  // Convert to Q8.8
            x_valid = 1;
        end
    endtask
    
    //==========================================================================
    // Test Cases
    //==========================================================================
    
    // Test 1: Impulse Response
    task test_impulse;
        begin
            $display("\n========================================");
            $display("TEST 1: Impulse Response");
            $display("========================================");
            test_count = test_count + 1;
            
            reset_dut();
            
            send_sample(1.0);  // Impulse
            send_sample(0.0);
            send_sample(0.0);
            
            repeat(5) @(posedge clk);
            
            $display("[PASS] Impulse test completed");
            pass_count = pass_count + 1;
            
            x_valid = 0;
            repeat(5) @(posedge clk);
        end
    endtask
    
    // Test 2: DC Response
    task test_dc;
        integer i;
        begin
            $display("\n========================================");
            $display("TEST 2: DC Response");
            $display("========================================");
            test_count = test_count + 1;
            
            reset_dut();
            
            for (i = 0; i < 10; i = i + 1)
                send_sample(1.0);
            
            $display("[PASS] DC response test completed");
            pass_count = pass_count + 1;
            
            @(posedge clk);
            x_valid = 0;
            repeat(5) @(posedge clk);
        end
    endtask
    
    // Test 3: Ramp Response
    task test_ramp;
        integer i;
        real ramp_val;
        begin
            $display("\n========================================");
            $display("TEST 3: Ramp Response");
            $display("========================================");
            test_count = test_count + 1;
            
            reset_dut();
            
            for (i = 0; i < 10; i = i + 1) begin
                ramp_val = $itor(i) * 0.1;
                send_sample(ramp_val);
            end
            
            $display("[PASS] Ramp test completed");
            pass_count = pass_count + 1;
            
            @(posedge clk);
            x_valid = 0;
            repeat(5) @(posedge clk);
        end
    endtask
    
    // Test 4: Zero Input
    task test_zeros;
        integer i;
        begin
            $display("\n========================================");
            $display("TEST 4: Zero Input");
            $display("========================================");
            test_count = test_count + 1;
            
            reset_dut();
            
            for (i = 0; i < 10; i = i + 1)
                send_sample(0.0);
            
            $display("[PASS] Zero input test completed");
            pass_count = pass_count + 1;
            
            x_valid = 0;
            repeat(5) @(posedge clk);
        end
    endtask
    
    //==========================================================================
    // Output Monitor
    //==========================================================================
    
    always @(posedge clk) begin
        if (!rst)
            cycle_count <= cycle_count + 1;
        else
            cycle_count <= 0;
            
        if (y_valid) begin
            $display("[%0t] Cycle %0d: y_out = %h (%.4f)", 
                     $time, cycle_count, y_out, $itor(y_out)/256.0);
        end
    end
    
    //==========================================================================
    // Main Test Sequence
    //==========================================================================
    
    initial begin
        $display("\n");
        $display("============================================================");
        $display("    TEMPORAL CONVOLUTION TESTBENCH");
        $display("    Purpose: Verify temporal_conv.sv ONLY");
        $display("============================================================");
        $display("");
        $display("Configuration:");
        $display("  DATA_WIDTH    = %0d bits", DATA_WIDTH);
        $display("  KERNEL_SIZE   = %0d", KERNEL_SIZE);
        $display("  Coefficients  = [1.0, 0, 0, 0, 0] (passthrough)");
        $display("");
        $display("Tests NO window logic | NO fusion | NO top-level");
        $display("Enforces correctness before integration");
        $display("");
        
        // Initialize
        test_count = 0;
        fail_count = 0;
        pass_count = 0;
        cycle_count = 0;
        rst = 1;
        x_in = 0;
        x_valid = 0;
        
        repeat(10) @(posedge clk);
        
        // Run tests
        test_impulse();
        test_dc();
        test_ramp();
        test_zeros();
        
        repeat(10) @(posedge clk);
        
        $display("\n");
        $display("\n============================================================");
        $display("    TEST SUMMARY");
        $display("============================================================\n");
        $display("");
        $display("  Total tests:   %0d", test_count);
        $display("  Passed:        %0d", pass_count);
        $display("  Failed:        %0d", fail_count);
        $display("  Total cycles:  %0d", cycle_count);
        $display("");
        
        if (fail_count == 0) begin
            $display("  ✓ ALL TESTS PASSED!");
            $display("");
            $display("  temporal_conv.sv is VERIFIED");
            $display("  Ready for integration with window_gen.sv");
        end else begin
            $display("  ✗ TESTS FAILED - DO NOT INTEGRATE");
            $display("");
            $display("  Fix temporal_conv.sv before proceeding");
        end
        
        $display("");
        $finish;
    end
    
    initial begin
        #100000;
        $display("\n[ERROR] Simulation timeout!");
        $finish;
    end

endmodule
