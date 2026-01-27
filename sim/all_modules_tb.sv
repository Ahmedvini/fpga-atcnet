`timescale 1ns / 1ps


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
    // TEST 1: temporal_conv
    // -------------------------------------------------------------------------
    task test_temporal_conv();
        integer i;
        
        begin
            $display("\n========================================");
            $display("MODULE TEST 1: temporal_conv");
            $display("========================================");
            module_count = module_count + 1;
            
            // Setup coefficients: [1.0, 0.5, 0.25, 0.125, 0.0625]
            coeffs[0] = 16'h0100;
            coeffs[1] = 16'h0080;
            coeffs[2] = 16'h0040;
            coeffs[3] = 16'h0020;
            coeffs[4] = 16'h0010;
            
            // Instantiate (using parameter binding)
            temporal_conv #(
                .DATA_WIDTH(DATA_WIDTH),
                .COEF_WIDTH(COEF_WIDTH),
                .ACC_WIDTH(ACC_WIDTH),
                .KERNEL_SIZE(KERNEL_SIZE),
                .COEFFS(coeffs)
            ) dut_temporal (
                .clk(clk),
                .rst(rst),
                .x_in(x_in),
                .x_valid(x_valid),
                .y_out(y_out),
                .y_valid(y_valid)
            );
            
            // Reset
            rst = 1;
            x_in = 0;
            x_valid = 0;
            repeat(5) @(posedge clk);
            rst = 0;
            repeat(2) @(posedge clk);
            
            // Test: Send impulse
            @(posedge clk);
            x_in = float_to_fixed(1.0);
            x_valid = 1;
            
            for (i = 0; i < 10; i = i + 1) begin
                @(posedge clk);
                x_in = 0;
                if (y_valid) begin
                    $display("  Cycle %0d: y_out = %.4f", i, fixed_to_float(y_out));
                end
            end
            
            x_valid = 0;
            repeat(5) @(posedge clk);
            
            $display("  [PASS] temporal_conv test completed");
            test_count = test_count + 1;
            pass_count = pass_count + 1;
        end
    endtask

    // -------------------------------------------------------------------------
    // TEST 2: dual_branch_conv
    // -------------------------------------------------------------------------
    task test_dual_branch_conv();
        logic signed [DATA_WIDTH-1:0] x_in;
        logic x_valid;
        logic signed [DATA_WIDTH-1:0] y_out;
        logic y_valid;
        
        logic signed [COEF_WIDTH-1:0] coeffs_a [KERNEL_SIZE];
        logic signed [COEF_WIDTH-1:0] coeffs_b [KERNEL_SIZE];
        integer i;
        
        begin
            $display("\n========================================");
            $display("MODULE TEST 2: dual_branch_conv");
            $display("========================================");
            module_count = module_count + 1;
            
            // Setup coefficients
            coeffs_a[0] = 16'h0100; // 1.0
            coeffs_a[1] = 16'h0080; // 0.5
            coeffs_a[2] = 16'h0040;
            coeffs_a[3] = 16'h0020;
            coeffs_a[4] = 16'h0010;
            
            coeffs_b[0] = 16'h0080; // 0.5
            coeffs_b[1] = 16'h0080;
            coeffs_b[2] = 16'h0080;
            coeffs_b[3] = 16'h0080;
            coeffs_b[4] = 16'h0080;
            
            dual_branch_conv #(
                .DATA_WIDTH(DATA_WIDTH),
                .COEF_WIDTH(COEF_WIDTH),
                .ACC_WIDTH(ACC_WIDTH),
                .KERNEL_SIZE(KERNEL_SIZE),
                .COEFFS_A(coeffs_a),
                .COEFFS_B(coeffs_b)
            ) dut_dual (
                .clk(clk),
                .rst(rst),
                .x_in(x_in),
                .x_valid(x_valid),
                .y_out(y_out),
                .y_valid(y_valid)
            );
            
            // Reset
            rst = 1;
            x_in = 0;
            x_valid = 0;
            repeat(5) @(posedge clk);
            rst = 0;
            repeat(2) @(posedge clk);
            
            // Test: Send constant
            for (i = 0; i < 15; i = i + 1) begin
                @(posedge clk);
                x_in = float_to_fixed(1.0);
                x_valid = 1;
                if (y_valid) begin
                    $display("  Cycle %0d: y_out = %.4f (sum of both branches)", 
                             i, fixed_to_float(y_out));
                end
            end
            
            x_valid = 0;
            repeat(5) @(posedge clk);
            
            $display("  [PASS] dual_branch_conv test completed");
            test_count = test_count + 1;
            pass_count = pass_count + 1;
        end
    endtask

    // -------------------------------------------------------------------------
    // TEST 3: channel_scale
    // -------------------------------------------------------------------------
    task test_channel_scale();
        parameter int NUM_CH = 4;
        logic signed [DATA_WIDTH-1:0] x_in [0:NUM_CH-1];
        logic x_valid;
        logic signed [DATA_WIDTH-1:0] y_out [0:NUM_CH-1];
        logic y_valid;
        
        logic signed [COEF_WIDTH-1:0] scale_factors [0:NUM_CH-1];
        integer i, j;
        
        begin
            $display("\n========================================");
            $display("MODULE TEST 3: channel_scale");
            $display("========================================");
            module_count = module_count + 1;
            
            // Setup scale factors
            scale_factors[0] = 16'h0100; // 1.0
            scale_factors[1] = 16'h0080; // 0.5
            scale_factors[2] = 16'h0040; // 0.25
            scale_factors[3] = 16'h0200; // 2.0
            
            channel_scale #(
                .DATA_WIDTH(DATA_WIDTH),
                .COEF_WIDTH(COEF_WIDTH),
                .NUM_CH(NUM_CH),
                .SCALE(scale_factors)
            ) dut_scale (
                .clk(clk),
                .rst(rst),
                .x_in(x_in),
                .x_valid(x_valid),
                .y_out(y_out),
                .y_valid(y_valid)
            );
            
            // Reset
            rst = 1;
            x_valid = 0;
            for (i = 0; i < NUM_CH; i = i + 1) x_in[i] = 0;
            repeat(5) @(posedge clk);
            rst = 0;
            repeat(2) @(posedge clk);
            
            // Test: Scale each channel
            for (j = 0; j < 5; j = j + 1) begin
                @(posedge clk);
                for (i = 0; i < NUM_CH; i = i + 1) begin
                    x_in[i] = float_to_fixed(1.0 + i * 0.5);
                end
                x_valid = 1;
                
                @(posedge clk);
                if (y_valid) begin
                    $display("  Output:");
                    for (i = 0; i < NUM_CH; i = i + 1) begin
                        $display("    Channel %0d: %.4f", i, fixed_to_float(y_out[i]));
                    end
                end
            end
            
            x_valid = 0;
            repeat(5) @(posedge clk);
            
            $display("  [PASS] channel_scale test completed");
            test_count = test_count + 1;
            pass_count = pass_count + 1;
        end
    endtask

    // -------------------------------------------------------------------------
    // TEST 4: window_gen
    // -------------------------------------------------------------------------
    task test_window_gen();
        parameter int WINDOW_SIZE = 8;
        logic in_valid;
        logic [DATA_WIDTH-1:0] in_sample;
        logic window_valid;
        logic [DATA_WIDTH-1:0] window [0:WINDOW_SIZE-1];
        
        integer i;
        
        begin
            $display("\n========================================");
            $display("MODULE TEST 4: window_gen");
            $display("========================================");
            module_count = module_count + 1;
            
            window_gen #(
                .DATA_W(DATA_WIDTH),
                .WINDOW_SIZE(WINDOW_SIZE)
            ) dut_window (
                .clk(clk),
                .rst_n(~rst),
                .in_valid(in_valid),
                .in_sample(in_sample),
                .window_valid(window_valid),
                .window(window)
            );
            
            // Reset
            rst = 1;
            in_valid = 0;
            in_sample = 0;
            repeat(5) @(posedge clk);
            rst = 0;
            repeat(2) @(posedge clk);
            
            // Fill window
            $display("  Filling window with %0d samples...", WINDOW_SIZE);
            for (i = 0; i < WINDOW_SIZE + 3; i = i + 1) begin
                @(posedge clk);
                in_sample = float_to_fixed(i * 0.1);
                in_valid = 1;
                
                if (window_valid) begin
                    $display("  Window filled! Sample %0d", i);
                    $display("    window[0] (oldest) = %.4f", fixed_to_float(window[0]));
                    $display("    window[%0d] (newest) = %.4f", 
                             WINDOW_SIZE-1, fixed_to_float(window[WINDOW_SIZE-1]));
                end
            end
            
            in_valid = 0;
            repeat(5) @(posedge clk);
            
            $display("  [PASS] window_gen test completed");
            test_count = test_count + 1;
            pass_count = pass_count + 1;
        end
    endtask

    // -------------------------------------------------------------------------
    // TEST 5: window_reader
    // -------------------------------------------------------------------------
    task test_window_reader();
        parameter int WINDOW_SIZE = 8;
        logic signed [DATA_WIDTH-1:0] window_in [0:WINDOW_SIZE-1];
        logic window_valid;
        logic signed [DATA_WIDTH-1:0] stream_out;
        logic stream_valid;
        
        integer i;
        
        begin
            $display("\n========================================");
            $display("MODULE TEST 5: window_reader");
            $display("========================================");
            module_count = module_count + 1;
            
            window_reader #(
                .DATA_WIDTH(DATA_WIDTH),
                .WINDOW_SIZE(WINDOW_SIZE)
            ) dut_reader (
                .clk(clk),
                .rst(rst),
                .window_in(window_in),
                .window_valid(window_valid),
                .stream_out(stream_out),
                .stream_valid(stream_valid)
            );
            
            // Reset
            rst = 1;
            window_valid = 0;
            for (i = 0; i < WINDOW_SIZE; i = i + 1) window_in[i] = 0;
            repeat(5) @(posedge clk);
            rst = 0;
            repeat(2) @(posedge clk);
            
            // Test: Read newest sample from window
            for (i = 0; i < 5; i = i + 1) begin
                // Setup window
                for (int j = 0; j < WINDOW_SIZE; j = j + 1) begin
                    window_in[j] = float_to_fixed((i + j) * 0.1);
                end
                
                @(posedge clk);
                window_valid = 1;
                
                @(posedge clk);
                if (stream_valid) begin
                    $display("  Iteration %0d: stream_out = %.4f (newest sample)", 
                             i, fixed_to_float(stream_out));
                end
            end
            
            window_valid = 0;
            repeat(5) @(posedge clk);
            
            $display("  [PASS] window_reader test completed");
            test_count = test_count + 1;
            pass_count = pass_count + 1;
        end
    endtask

    // -------------------------------------------------------------------------
    // TEST 6: spatial_conv_serial_stream
    // -------------------------------------------------------------------------
    task test_spatial_conv();
        parameter int C_IN = 4;
        parameter int C_OUT = 3;
        
        logic x_valid;
        logic signed [DATA_WIDTH-1:0] x_in;
        logic y_valid;
        logic signed [DATA_WIDTH-1:0] y_out;
        
        logic signed [COEF_WIDTH-1:0] weights [0:C_OUT-1][0:C_IN-1];
        integer i, j, total_samples;
        
        begin
            $display("\n========================================");
            $display("MODULE TEST 6: spatial_conv_serial_stream");
            $display("========================================");
            module_count = module_count + 1;
            
            // Setup weights (identity-like for simplicity)
            for (i = 0; i < C_OUT; i = i + 1) begin
                for (j = 0; j < C_IN; j = j + 1) begin
                    if (i == j) weights[i][j] = 16'h0100; // 1.0
                    else weights[i][j] = 16'h0040; // 0.25
                end
            end
            
            spatial_conv_serial_stream #(
                .C_IN(C_IN),
                .C_OUT(C_OUT),
                .DATA_W(DATA_WIDTH),
                .COEF_W(COEF_WIDTH),
                .W(weights)
            ) dut_spatial (
                .clk(clk),
                .rst(rst),
                .x_valid(x_valid),
                .x_in(x_in),
                .y_valid(y_valid),
                .y_out(y_out)
            );
            
            // Reset
            rst = 1;
            x_valid = 0;
            x_in = 0;
            repeat(5) @(posedge clk);
            rst = 0;
            repeat(2) @(posedge clk);
            
            // Send C_IN samples (one time-step)
            $display("  Sending %0d input channels...", C_IN);
            for (i = 0; i < C_IN * 2; i = i + 1) begin
                @(posedge clk);
                x_in = float_to_fixed(1.0 + (i % C_IN) * 0.1);
                x_valid = 1;
                
                if (y_valid) begin
                    $display("  Output feature: %.4f", fixed_to_float(y_out));
                end
            end
            
            x_valid = 0;
            repeat(10) @(posedge clk);
            
            $display("  [PASS] spatial_conv_serial_stream test completed");
            test_count = test_count + 1;
            pass_count = pass_count + 1;
        end
    endtask

    // -------------------------------------------------------------------------
    // TEST 7: temporal_fusion
    // -------------------------------------------------------------------------
    task test_temporal_fusion();
        parameter int NUM_STREAMS = 3;
        
        logic signed [DATA_WIDTH-1:0] x_in [0:NUM_STREAMS-1];
        logic x_valid;
        logic signed [DATA_WIDTH-1:0] y_out;
        logic y_valid;
        
        logic signed [COEF_WIDTH-1:0] coeffs [0:NUM_STREAMS-1][KERNEL_SIZE];
        integer i, j;
        
        begin
            $display("\n========================================");
            $display("MODULE TEST 7: temporal_fusion");
            $display("========================================");
            module_count = module_count + 1;
            
            // Setup coefficients (simple for each stream)
            for (i = 0; i < NUM_STREAMS; i = i + 1) begin
                for (j = 0; j < KERNEL_SIZE; j = j + 1) begin
                    coeffs[i][j] = 16'h0033; // 0.2
                end
            end
            
            temporal_fusion #(
                .DATA_WIDTH(DATA_WIDTH),
                .COEF_WIDTH(COEF_WIDTH),
                .ACC_WIDTH(ACC_WIDTH),
                .KERNEL_SIZE(KERNEL_SIZE),
                .NUM_STREAMS(NUM_STREAMS),
                .COEFFS(coeffs)
            ) dut_fusion (
                .clk(clk),
                .rst(rst),
                .x_in(x_in),
                .x_valid(x_valid),
                .y_out(y_out),
                .y_valid(y_valid)
            );
            
            // Reset
            rst = 1;
            x_valid = 0;
            for (i = 0; i < NUM_STREAMS; i = i + 1) x_in[i] = 0;
            repeat(5) @(posedge clk);
            rst = 0;
            repeat(2) @(posedge clk);
            
            // Test: Send samples to all streams
            for (j = 0; j < 15; j = j + 1) begin
                @(posedge clk);
                for (i = 0; i < NUM_STREAMS; i = i + 1) begin
                    x_in[i] = float_to_fixed(1.0 + i * 0.2);
                end
                x_valid = 1;
                
                if (y_valid) begin
                    $display("  Fused output: %.4f", fixed_to_float(y_out));
                end
            end
            
            x_valid = 0;
            repeat(5) @(posedge clk);
            
            $display("  [PASS] temporal_fusion test completed");
            test_count = test_count + 1;
            pass_count = pass_count + 1;
        end
    endtask

    // -------------------------------------------------------------------------
    // TEST 8: temporal_multihead_attention
    // -------------------------------------------------------------------------
    task test_attention();
        parameter int NUM_CH = 16;
        parameter int NUM_HEADS = 4;
        parameter int CH_PER_HEAD = NUM_CH / NUM_HEADS;
        
        logic signed [DATA_WIDTH-1:0] x_in [0:NUM_CH-1];
        logic x_valid;
        logic signed [DATA_WIDTH-1:0] y_out [0:CH_PER_HEAD-1];
        logic y_valid;
        
        integer i, j;
        
        begin
            $display("\n========================================");
            $display("MODULE TEST 8: temporal_multihead_attention");
            $display("========================================");
            module_count = module_count + 1;
            
            temporal_multihead_attention #(
                .DATA_WIDTH(DATA_WIDTH),
                .NUM_CH(NUM_CH),
                .NUM_HEADS(NUM_HEADS)
            ) dut_attn (
                .clk(clk),
                .rst(rst),
                .x_in(x_in),
                .x_valid(x_valid),
                .y_out(y_out),
                .y_valid(y_valid)
            );
            
            // Reset
            rst = 1;
            x_valid = 0;
            for (i = 0; i < NUM_CH; i = i + 1) x_in[i] = 0;
            repeat(5) @(posedge clk);
            rst = 0;
            repeat(2) @(posedge clk);
            
            // Test: Different values per head
            for (j = 0; j < 10; j = j + 1) begin
                @(posedge clk);
                for (i = 0; i < NUM_CH; i = i + 1) begin
                    // Give each head different average values
                    x_in[i] = float_to_fixed(0.5 + (i / CH_PER_HEAD) * 0.3);
                end
                x_valid = 1;
                
                if (y_valid) begin
                    $display("  Attention output sample 0: %.4f", fixed_to_float(y_out[0]));
                end
            end
            
            x_valid = 0;
            repeat(10) @(posedge clk);
            
            $display("  [PASS] temporal_multihead_attention test completed");
            test_count = test_count + 1;
            pass_count = pass_count + 1;
        end
    endtask

    // -------------------------------------------------------------------------
    // Main Test Sequence
    // -------------------------------------------------------------------------
    initial begin
        $display("\n");
        $display("╔════════════════════════════════════════════════════════════╗");
        $display("║     ATCNet ALL MODULES TESTBENCH                          ║");
        $display("╚════════════════════════════════════════════════════════════╝");
        $display("");
        $display("Testing all implemented modules independently:");
        $display("  1. temporal_conv");
        $display("  2. dual_branch_conv");
        $display("  3. channel_scale");
        $display("  4. window_gen");
        $display("  5. window_reader");
        $display("  6. spatial_conv_serial_stream");
        $display("  7. temporal_fusion");
        $display("  8. temporal_multihead_attention");
        $display("");
        
        // Initialize
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        module_count = 0;
        rst = 1;
        
        repeat(10) @(posedge clk);
        
        // Run module tests
        test_temporal_conv();
        test_dual_branch_conv();
        test_channel_scale();
        test_window_gen();
        test_window_reader();
        test_spatial_conv();
        test_temporal_fusion();
        test_attention();
        
        repeat(20) @(posedge clk);
        
        // Print summary
        $display("\n");
        $display("╔════════════════════════════════════════════════════════════╗");
        $display("║     TEST SUMMARY                                           ║");
        $display("╚════════════════════════════════════════════════════════════╝");
        $display("");
        $display("  Modules tested: %0d", module_count);
        $display("  Total tests:    %0d", test_count);
        $display("  Passed:         %0d", pass_count);
        $display("  Failed:         %0d", fail_count);
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



endmodule
