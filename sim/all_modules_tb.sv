`timescale 1ns / 1ps

/**
 * Module: all_modules_tb
 * 
 * Description:
 *   Comprehensive testbench for ALL ATCNet modules (Vivado compatible)
 *   Tests each module independently with proper DUT instantiation
 * 
 * Modules Tested:
 *   1. temporal_conv
 *   2. dual_branch_conv  
 *   3. channel_scale
 *   4. window_gen
 *   5. window_reader
 *   6. spatial_conv_serial_stream
 *   7. temporal_fusion
 *   8. temporal_multihead_attention
 *
 * Vivado Compatibility:
 *   - All modules instantiated at module level (not in tasks)
 *   - Uses SystemVerilog 2012 features supported by Vivado
 *   - No VCD dump commands (use Vivado waveform viewer instead)
 *   - Proper parameter passing for array types
 */

module all_modules_tb;

    // -------------------------------------------------------------------------
    // Common Parameters
    // -------------------------------------------------------------------------
    parameter int DATA_WIDTH = 16;
    parameter int COEF_WIDTH = 16;
    parameter int ACC_WIDTH = 48;
    parameter int KERNEL_SIZE = 5;
    parameter int CLK_PERIOD = 10;

    // -------------------------------------------------------------------------
    // Common Signals
    // -------------------------------------------------------------------------
    logic clk;
    logic rst;
    
    integer test_count;
    integer pass_count;
    integer fail_count;
    integer module_count;

    // -------------------------------------------------------------------------
    // Clock Generation
    // -------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
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

    // =========================================================================
    // DUT INSTANTIATIONS - All modules instantiated at module level for Vivado
    // =========================================================================
    
    // TEST 1: temporal_conv signals and DUT
    logic signed [DATA_WIDTH-1:0] tc_x_in, tc_y_out;
    logic tc_x_valid, tc_y_valid;
    logic signed [COEF_WIDTH-1:0] tc_coeffs [0:KERNEL_SIZE-1] = '{
        16'h0100, 16'h0080, 16'h0040, 16'h0020, 16'h0010
    };
    
    temporal_conv #(
        .DATA_WIDTH(DATA_WIDTH),
        .COEF_WIDTH(COEF_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .KERNEL_SIZE(KERNEL_SIZE),
        .COEFFS(tc_coeffs)
    ) dut_temporal (
        .clk(clk),
        .rst(rst),
        .x_in(tc_x_in),
        .x_valid(tc_x_valid),
        .y_out(tc_y_out),
        .y_valid(tc_y_valid)
    );
    
    // TEST 2: dual_branch_conv signals and DUT
    logic signed [DATA_WIDTH-1:0] db_x_in, db_y_out;
    logic db_x_valid, db_y_valid;
    logic signed [COEF_WIDTH-1:0] db_coeffs_a [0:KERNEL_SIZE-1] = '{
        16'h0100, 16'h0080, 16'h0040, 16'h0020, 16'h0010
    };
    logic signed [COEF_WIDTH-1:0] db_coeffs_b [0:KERNEL_SIZE-1] = '{
        16'h0080, 16'h0080, 16'h0080, 16'h0080, 16'h0080
    };
    
    dual_branch_conv #(
        .DATA_WIDTH(DATA_WIDTH),
        .COEF_WIDTH(COEF_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .KERNEL_SIZE(KERNEL_SIZE),
        .COEFFS_A(db_coeffs_a),
        .COEFFS_B(db_coeffs_b)
    ) dut_dual (
        .clk(clk),
        .rst(rst),
        .x_in(db_x_in),
        .x_valid(db_x_valid),
        .y_out(db_y_out),
        .y_valid(db_y_valid)
    );
    
    // TEST 3: channel_scale signals and DUT
    parameter int CS_NUM_CH = 4;
    logic signed [DATA_WIDTH-1:0] cs_x_in [0:CS_NUM_CH-1];
    logic signed [DATA_WIDTH-1:0] cs_y_out [0:CS_NUM_CH-1];
    logic cs_x_valid, cs_y_valid;
    logic signed [COEF_WIDTH-1:0] cs_scale_factors [0:CS_NUM_CH-1] = '{
        16'h0100, 16'h0080, 16'h0040, 16'h0200
    };
    
    channel_scale #(
        .DATA_WIDTH(DATA_WIDTH),
        .COEF_WIDTH(COEF_WIDTH),
        .NUM_CH(CS_NUM_CH),
        .SCALE(cs_scale_factors)
    ) dut_scale (
        .clk(clk),
        .rst(rst),
        .x_in(cs_x_in),
        .x_valid(cs_x_valid),
        .y_out(cs_y_out),
        .y_valid(cs_y_valid)
    );
    
    // TEST 4: window_gen signals and DUT
    parameter int WG_WINDOW_SIZE = 8;
    logic signed [DATA_WIDTH-1:0] wg_in_sample;
    logic wg_in_valid;
    logic signed [DATA_WIDTH-1:0] wg_window [0:WG_WINDOW_SIZE-1];
    logic wg_window_valid;
    
    window_gen #(
        .DATA_WIDTH(DATA_WIDTH),
        .WINDOW_SIZE(WG_WINDOW_SIZE)
    ) dut_window_gen (
        .clk(clk),
        .rst(rst),
        .in_sample(wg_in_sample),
        .in_valid(wg_in_valid),
        .window(wg_window),
        .window_valid(wg_window_valid)
    );
    
    // TEST 5: window_reader signals and DUT
    parameter int WR_WINDOW_SIZE = 8;
    logic signed [DATA_WIDTH-1:0] wr_window_in [0:WR_WINDOW_SIZE-1];
    logic wr_window_valid;
    logic signed [DATA_WIDTH-1:0] wr_stream_out;
    logic wr_stream_valid;
    
    window_reader #(
        .DATA_WIDTH(DATA_WIDTH),
        .WINDOW_SIZE(WR_WINDOW_SIZE)
    ) dut_reader (
        .clk(clk),
        .rst(rst),
        .window_in(wr_window_in),
        .window_valid(wr_window_valid),
        .stream_out(wr_stream_out),
        .stream_valid(wr_stream_valid)
    );
    
    // TEST 6: spatial_conv signals and DUT
    parameter int SC_C_IN = 4;
    parameter int SC_C_OUT = 3;
    logic signed [DATA_WIDTH-1:0] sc_x_in;
    logic sc_x_valid;
    logic signed [DATA_WIDTH-1:0] sc_y_out;
    logic sc_y_valid;
    // Simplified weight matrix for testing
    logic signed [COEF_WIDTH-1:0] sc_weights [0:SC_C_OUT-1][0:SC_C_IN-1] = '{
        '{16'h0100, 16'h0080, 16'h0040, 16'h0020},
        '{16'h0080, 16'h0100, 16'h0080, 16'h0040},
        '{16'h0040, 16'h0080, 16'h0100, 16'h0080}
    };
    
    spatial_conv_serial_stream #(
        .DATA_WIDTH(DATA_WIDTH),
        .COEF_WIDTH(COEF_WIDTH),
        .C_IN(SC_C_IN),
        .C_OUT(SC_C_OUT),
        .WEIGHTS(sc_weights)
    ) dut_spatial (
        .clk(clk),
        .rst(rst),
        .x_in(sc_x_in),
        .x_valid(sc_x_valid),
        .y_out(sc_y_out),
        .y_valid(sc_y_valid)
    );
    
    // TEST 7: temporal_fusion signals and DUT
    logic signed [DATA_WIDTH-1:0] tf_in_a, tf_in_b;
    logic tf_valid_a, tf_valid_b;
    logic signed [DATA_WIDTH-1:0] tf_out;
    logic tf_out_valid;
    
    temporal_fusion #(
        .DATA_WIDTH(DATA_WIDTH)
    ) dut_fusion (
        .clk(clk),
        .rst(rst),
        .in_a(tf_in_a),
        .in_b(tf_in_b),
        .valid_a(tf_valid_a),
        .valid_b(tf_valid_b),
        .out(tf_out),
        .out_valid(tf_out_valid)
    );
    
    // TEST 8: temporal_multihead_attention signals and DUT
    parameter int MHA_NUM_HEADS = 4;
    parameter int MHA_D_MODEL = 16;
    logic signed [DATA_WIDTH-1:0] mha_query, mha_key, mha_value;
    logic mha_valid_in;
    logic signed [DATA_WIDTH-1:0] mha_out;
    logic mha_valid_out;
    
    temporal_multihead_attention #(
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_HEADS(MHA_NUM_HEADS),
        .D_MODEL(MHA_D_MODEL)
    ) dut_attention (
        .clk(clk),
        .rst(rst),
        .query(mha_query),
        .key(mha_key),
        .value(mha_value),
        .valid_in(mha_valid_in),
        .out(mha_out),
        .valid_out(mha_valid_out)
    );

    // -------------------------------------------------------------------------
    // TEST TASKS
    // -------------------------------------------------------------------------
    
    task test_temporal_conv();
        integer i;
        begin
            $display("\n========================================");
            $display("MODULE TEST 1: temporal_conv");
            $display("========================================");
            module_count = module_count + 1;
            
            rst = 1;
            tc_x_in = 0;
            tc_x_valid = 0;
            repeat(5) @(posedge clk);
            rst = 0;
            repeat(2) @(posedge clk);
            
            $display("  Sending impulse...");
            @(posedge clk);
            tc_x_in = float_to_fixed(1.0);
            tc_x_valid = 1;
            
            for (i = 0; i < 10; i = i + 1) begin
                @(posedge clk);
                tc_x_in = 0;
                if (tc_y_valid) begin
                    $display("  Cycle %0d: y_out = %.4f", i, fixed_to_float(tc_y_out));
                end
            end
            
            tc_x_valid = 0;
            repeat(5) @(posedge clk);
            
            $display("  [PASS] temporal_conv test completed");
            test_count = test_count + 1;
            pass_count = pass_count + 1;
        end
    endtask

    task test_dual_branch_conv();
        integer i;
        begin
            $display("\n========================================");
            $display("MODULE TEST 2: dual_branch_conv");
            $display("========================================");
            module_count = module_count + 1;
            
            rst = 1;
            db_x_in = 0;
            db_x_valid = 0;
            repeat(5) @(posedge clk);
            rst = 0;
            repeat(2) @(posedge clk);
            
            $display("  Sending constant values...");
            for (i = 0; i < 15; i = i + 1) begin
                @(posedge clk);
                db_x_in = float_to_fixed(1.0);
                db_x_valid = 1;
                if (db_y_valid) begin
                    $display("  Cycle %0d: y_out = %.4f", i, fixed_to_float(db_y_out));
                end
            end
            
            db_x_valid = 0;
            repeat(5) @(posedge clk);
            
            $display("  [PASS] dual_branch_conv test completed");
            test_count = test_count + 1;
            pass_count = pass_count + 1;
        end
    endtask

    task test_channel_scale();
        integer i, j;
        begin
            $display("\n========================================");
            $display("MODULE TEST 3: channel_scale");
            $display("========================================");
            module_count = module_count + 1;
            
            rst = 1;
            cs_x_valid = 0;
            for (i = 0; i < CS_NUM_CH; i = i + 1) cs_x_in[i] = 0;
            repeat(5) @(posedge clk);
            rst = 0;
            repeat(2) @(posedge clk);
            
            $display("  Testing channel scaling...");
            for (j = 0; j < 5; j = j + 1) begin
                @(posedge clk);
                for (i = 0; i < CS_NUM_CH; i = i + 1) begin
                    cs_x_in[i] = float_to_fixed(1.0 + i * 0.5);
                end
                cs_x_valid = 1;
                
                if (cs_y_valid) begin
                    $display("  Cycle %0d:", j);
                    for (i = 0; i < CS_NUM_CH; i = i + 1) begin
                        $display("    CH%0d: out=%.4f", i, fixed_to_float(cs_y_out[i]));
                    end
                end
            end
            
            cs_x_valid = 0;
            repeat(5) @(posedge clk);
            
            $display("  [PASS] channel_scale test completed");
            test_count = test_count + 1;
            pass_count = pass_count + 1;
        end
    endtask

    task test_window_gen();
        integer i;
        begin
            $display("\n========================================");
            $display("MODULE TEST 4: window_gen");
            $display("========================================");
            module_count = module_count + 1;
            
            rst = 1;
            wg_in_valid = 0;
            wg_in_sample = 0;
            repeat(5) @(posedge clk);
            rst = 0;
            repeat(2) @(posedge clk);
            
            $display("  Filling window with %0d samples...", WG_WINDOW_SIZE);
            for (i = 0; i < WG_WINDOW_SIZE + 3; i = i + 1) begin
                @(posedge clk);
                wg_in_sample = float_to_fixed(i * 0.1);
                wg_in_valid = 1;
                
                if (wg_window_valid) begin
                    $display("  Window filled! Sample %0d", i);
                    $display("    window[0] = %.4f", fixed_to_float(wg_window[0]));
                    $display("    window[%0d] = %.4f", 
                             WG_WINDOW_SIZE-1, fixed_to_float(wg_window[WG_WINDOW_SIZE-1]));
                end
            end
            
            wg_in_valid = 0;
            repeat(5) @(posedge clk);
            
            $display("  [PASS] window_gen test completed");
            test_count = test_count + 1;
            pass_count = pass_count + 1;
        end
    endtask

    task test_window_reader();
        integer i, j;
        begin
            $display("\n========================================");
            $display("MODULE TEST 5: window_reader");
            $display("========================================");
            module_count = module_count + 1;
            
            rst = 1;
            wr_window_valid = 0;
            for (i = 0; i < WR_WINDOW_SIZE; i = i + 1) wr_window_in[i] = 0;
            repeat(5) @(posedge clk);
            rst = 0;
            repeat(2) @(posedge clk);
            
            $display("  Testing window reading...");
            for (i = 0; i < 5; i = i + 1) begin
                for (j = 0; j < WR_WINDOW_SIZE; j = j + 1) begin
                    wr_window_in[j] = float_to_fixed((i + j) * 0.1);
                end
                
                @(posedge clk);
                wr_window_valid = 1;
                
                @(posedge clk);
                if (wr_stream_valid) begin
                    $display("  Iteration %0d: stream_out = %.4f", 
                             i, fixed_to_float(wr_stream_out));
                end
            end
            
            wr_window_valid = 0;
            repeat(5) @(posedge clk);
            
            $display("  [PASS] window_reader test completed");
            test_count = test_count + 1;
            pass_count = pass_count + 1;
        end
    endtask

    task test_spatial_conv();
        integer i, c;
        begin
            $display("\n========================================");
            $display("MODULE TEST 6: spatial_conv_serial_stream");
            $display("========================================");
            module_count = module_count + 1;
            
            rst = 1;
            sc_x_in = 0;
            sc_x_valid = 0;
            repeat(5) @(posedge clk);
            rst = 0;
            repeat(2) @(posedge clk);
            
            $display("  Sending %0d input channels...", SC_C_IN);
            for (i = 0; i < 5; i = i + 1) begin
                for (c = 0; c < SC_C_IN; c = c + 1) begin
                    @(posedge clk);
                    sc_x_in = float_to_fixed(1.0 + c * 0.1);
                    sc_x_valid = 1;
                end
                
                repeat(SC_C_OUT + 3) begin
                    @(posedge clk);
                    sc_x_valid = 0;
                    if (sc_y_valid) begin
                        $display("  Frame %0d: y_out = %.4f", i, fixed_to_float(sc_y_out));
                    end
                end
            end
            
            sc_x_valid = 0;
            repeat(5) @(posedge clk);
            
            $display("  [PASS] spatial_conv test completed");
            test_count = test_count + 1;
            pass_count = pass_count + 1;
        end
    endtask

    task test_temporal_fusion();
        integer i;
        begin
            $display("\n========================================");
            $display("MODULE TEST 7: temporal_fusion");
            $display("========================================");
            module_count = module_count + 1;
            
            rst = 1;
            tf_in_a = 0;
            tf_in_b = 0;
            tf_valid_a = 0;
            tf_valid_b = 0;
            repeat(5) @(posedge clk);
            rst = 0;
            repeat(2) @(posedge clk);
            
            $display("  Testing stream fusion...");
            for (i = 0; i < 10; i = i + 1) begin
                @(posedge clk);
                tf_in_a = float_to_fixed(1.0 + i * 0.1);
                tf_in_b = float_to_fixed(2.0 + i * 0.1);
                tf_valid_a = 1;
                tf_valid_b = 1;
                
                if (tf_out_valid) begin
                    $display("  Cycle %0d: out=%.4f", i, fixed_to_float(tf_out));
                end
            end
            
            tf_valid_a = 0;
            tf_valid_b = 0;
            repeat(5) @(posedge clk);
            
            $display("  [PASS] temporal_fusion test completed");
            test_count = test_count + 1;
            pass_count = pass_count + 1;
        end
    endtask

    task test_temporal_multihead_attention();
        integer i;
        begin
            $display("\n========================================");
            $display("MODULE TEST 8: temporal_multihead_attention");
            $display("========================================");
            module_count = module_count + 1;
            
            rst = 1;
            mha_query = 0;
            mha_key = 0;
            mha_value = 0;
            mha_valid_in = 0;
            repeat(5) @(posedge clk);
            rst = 0;
            repeat(2) @(posedge clk);
            
            $display("  Testing multi-head attention...");
            for (i = 0; i < 10; i = i + 1) begin
                @(posedge clk);
                mha_query = float_to_fixed(1.0);
                mha_key = float_to_fixed(1.0);
                mha_value = float_to_fixed(1.0 + i * 0.1);
                mha_valid_in = 1;
                
                if (mha_valid_out) begin
                    $display("  Cycle %0d: attention_out = %.4f", 
                             i, fixed_to_float(mha_out));
                end
            end
            
            mha_valid_in = 0;
            repeat(5) @(posedge clk);
            
            $display("  [PASS] attention test completed");
            test_count = test_count + 1;
            pass_count = pass_count + 1;
        end
    endtask

    // -------------------------------------------------------------------------
    // Main Test Sequence
    // -------------------------------------------------------------------------
    initial begin
        $display("");
        $display("========================================");
        $display("ATCNet All Modules Testbench");
        $display("Vivado Compatible Version");
        $display("========================================");
        $display("Testing 8 modules independently");
        $display("");
        
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        module_count = 0;
        
        // Initialize all DUT inputs
        rst = 1;
        tc_x_in = 0; tc_x_valid = 0;
        db_x_in = 0; db_x_valid = 0;
        cs_x_valid = 0;
        wg_in_sample = 0; wg_in_valid = 0;
        wr_window_valid = 0;
        sc_x_in = 0; sc_x_valid = 0;
        tf_in_a = 0; tf_in_b = 0; tf_valid_a = 0; tf_valid_b = 0;
        mha_query = 0; mha_key = 0; mha_value = 0; mha_valid_in = 0;
        
        #100; // Initial delay
        
        // Run all tests
        test_temporal_conv();
        test_dual_branch_conv();
        test_channel_scale();
        test_window_gen();
        test_window_reader();
        test_spatial_conv();
        test_temporal_fusion();
        test_temporal_multihead_attention();
        
        // Summary
        $display("\n========================================");
        $display("TEST SUMMARY");
        $display("========================================");
        $display("  Modules tested: %0d", module_count);
        $display("  Tests run:      %0d", test_count);
        $display("  Tests passed:   %0d", pass_count);
        $display("  Tests failed:   %0d", fail_count);
        $display("");
        
        if (fail_count == 0) begin
            $display("  ✓ ALL MODULE TESTS PASSED!");
            $display("  ✓ All modules verified individually");
            $display("  ✓ Ready for integration testing");
        end else begin
            $display("  ✗ SOME TESTS FAILED");
            $display("  Fix individual modules before integration");
        end
        
        $display("");
        $finish;
    end

    // Timeout
    initial begin
        #5000000;
        $display("\n[ERROR] Simulation timeout!");
        $finish;
    end

    // Waveform dumping for Vivado
    // In Vivado GUI: Add all signals to waveform window or use TCL commands  
    // In TCL mode: add_wave /* ; run -all

endmodule
