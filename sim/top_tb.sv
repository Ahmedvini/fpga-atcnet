`timescale 1ns / 1ps

module top_tb;

    parameter int DATA_WIDTH  = 16;
    parameter int COEF_WIDTH  = 16;
    parameter int ACC_WIDTH   = 48;
    parameter int WINDOW_SIZE = 32;
    parameter int KERNEL_SIZE = 5;
    parameter int NUM_CH      = 1;
    parameter int CLK_PERIOD  = 10;

    parameter logic signed [COEF_WIDTH-1:0] CONV_COEFFS_A [0:KERNEL_SIZE-1] = '{
        16'h0100, 16'h0080, 16'h0040, 16'h0020, 16'h0010
    };

    parameter logic signed [COEF_WIDTH-1:0] CONV_COEFFS_B [0:KERNEL_SIZE-1] = '{
        16'h0080, 16'h0080, 16'h0080, 16'h0080, 16'h0080
    };

    parameter logic signed [COEF_WIDTH-1:0] SCALE_FACTORS [0:NUM_CH-1] = '{16'h0100};

    logic clk;
    logic rst;

    int test_count;
    int pass_count;
    int fail_count;
    int cycle_count;

    logic signed [DATA_WIDTH-1:0] in_sample;
    logic                         in_valid;
    logic signed [DATA_WIDTH-1:0] out_sample;
    logic                         out_valid;
    logic signed [DATA_WIDTH-1:0] output_history [0:1023];
    integer output_count;
    integer first_input_cycle;
    integer first_output_cycle;
    integer measured_latency;

    logic         sha_start;
    logic [511:0] sha_data_in;
    logic         sha_use_init;
    logic [255:0] sha_init_hash;
    logic [255:0] sha_digest;
    logic         sha_digest_valid;
    logic         sha_busy;

    logic         hmac_start;
    logic [511:0] hmac_key;
    logic [7:0]   hmac_key_len;
    logic         hmac_key_is_hashed;
    logic [511:0] hmac_msg_data;
    logic [63:0]  hmac_msg_len;
    logic         hmac_msg_valid;
    logic         hmac_msg_last;
    logic [255:0] hmac_out;
    logic         hmac_valid;
    logic         hmac_busy_sig;

    logic         hc_log_valid;
    logic [255:0] hc_log_data;
    logic [255:0] hc_genesis_hash;
    logic         hc_init_chain;
    logic [255:0] hc_chain_hash;
    logic [15:0]  hc_entry_count;
    logic         hc_hash_valid;
    logic         hc_busy;
    logic         hc_verify_start;
    logic [255:0] hc_verify_prev_hash;
    logic [255:0] hc_verify_log_data;
    logic [255:0] hc_verify_expected;
    logic         hc_verify_ok;
    logic         hc_verify_fail;

    logic [511:0]  sb_bitstream_block;
    logic          sb_bitstream_valid;
    logic          sb_bitstream_last;
    logic [63:0]   sb_bitstream_len;
    logic [2047:0] sb_signature;
    logic [2047:0] sb_pub_exp;
    logic [11:0]   sb_pub_exp_bits;
    logic [2047:0] sb_modulus;
    logic          sb_boot_start;
    logic          sb_boot_allow;
    logic          sb_boot_deny;
    logic          sb_boot_busy;
    logic [255:0]  sb_boot_hash_out;

    logic         sec_encrypt_start;
    logic         sec_decrypt_start;
    logic [255:0] sec_aes_key;
    logic [511:0] sec_hmac_key;
    logic [7:0]   sec_hmac_key_len;
    logic [95:0]  sec_nonce_seed;
    logic         sec_nonce_increment;
    logic [95:0]  sec_current_nonce;
    logic         sec_eeg_data_valid;
    logic [127:0] sec_eeg_data_in;
    logic         sec_eeg_data_last;
    logic [63:0]  sec_eeg_data_len;
    logic         sec_metadata_valid;
    logic [127:0] sec_metadata_block;
    logic [63:0]  sec_metadata_len;
    logic [127:0] sec_data_out;
    logic         sec_data_out_valid;
    logic [95:0]  sec_storage_nonce;
    logic [127:0] sec_storage_gcm_tag;
    logic [255:0] sec_storage_hmac;
    logic         sec_storage_ready;
    logic [95:0]  sec_decrypt_nonce;
    logic [127:0] sec_decrypt_gcm_tag;
    logic [255:0] sec_decrypt_hmac;
    logic         sec_auth_verified;
    logic         sec_auth_failed;
    logic         sec_hmac_check_ok;
    logic         sec_gcm_check_ok;
    logic         sec_busy;
    logic         sec_done;
    logic         sec_error;
    logic [255:0] sec_chain_genesis;
    logic         sec_chain_init;
    logic [255:0] sec_chain_hash_out;
    logic [15:0]  sec_chain_entry_count;
    logic         sec_chain_hash_valid;
    logic         sec_chain_verify_start;
    logic [255:0] sec_chain_verify_prev_hash;
    logic [255:0] sec_chain_verify_log_data;
    logic [255:0] sec_chain_verify_expected;
    logic         sec_chain_verify_ok;
    logic         sec_chain_verify_fail;
    logic [511:0]  sec_boot_bitstream_block;
    logic          sec_boot_bitstream_valid;
    logic          sec_boot_bitstream_last;
    logic [63:0]   sec_boot_bitstream_len;
    logic [2047:0] sec_boot_public_key_n;
    logic [2047:0] sec_boot_signature;
    logic [2047:0] sec_boot_pub_exp;
    logic [11:0]   sec_boot_pub_exp_bits;
    logic          sec_boot_verify_start;
    logic          sec_boot_allow;
    logic          sec_boot_deny;
    logic          sec_boot_busy;
    logic [255:0]  sec_boot_hash_out;
    logic [127:0]  sec_last_data_out;
    integer        sec_output_count;

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

    sha256_core u_sha256_dut (
        .clk          (clk),
        .rst          (rst),
        .start        (sha_start),
        .data_in      (sha_data_in),
        .use_init_hash(sha_use_init),
        .init_hash    (sha_init_hash),
        .digest_out   (sha_digest),
        .digest_valid (sha_digest_valid),
        .busy         (sha_busy)
    );

    hmac_sha256 u_hmac_dut (
        .clk          (clk),
        .rst          (rst),
        .start        (hmac_start),
        .key          (hmac_key),
        .key_len      (hmac_key_len),
        .key_is_hashed(hmac_key_is_hashed),
        .msg_data     (hmac_msg_data),
        .msg_len      (hmac_msg_len),
        .msg_valid    (hmac_msg_valid),
        .msg_last     (hmac_msg_last),
        .hmac_out     (hmac_out),
        .hmac_valid   (hmac_valid),
        .busy         (hmac_busy_sig)
    );

    sha256_hash_chain u_hchain_dut (
        .clk              (clk),
        .rst              (rst),
        .log_valid        (hc_log_valid),
        .log_data         (hc_log_data),
        .genesis_hash     (hc_genesis_hash),
        .init_chain       (hc_init_chain),
        .chain_hash       (hc_chain_hash),
        .entry_count      (hc_entry_count),
        .hash_valid       (hc_hash_valid),
        .busy             (hc_busy),
        .verify_start     (hc_verify_start),
        .verify_prev_hash (hc_verify_prev_hash),
        .verify_log_data  (hc_verify_log_data),
        .verify_expected  (hc_verify_expected),
        .verify_ok        (hc_verify_ok),
        .verify_fail      (hc_verify_fail)
    );

    secure_boot #(
        .KEY_BITS(2048)
    ) u_secure_boot_dut (
        .clk              (clk),
        .rst              (rst),
        .boot_start       (sb_boot_start),
        .bitstream_block  (sb_bitstream_block),
        .bitstream_valid  (sb_bitstream_valid),
        .bitstream_last   (sb_bitstream_last),
        .bitstream_len    (sb_bitstream_len),
        .rsa_signature    (sb_signature),
        .rsa_pub_exp      (sb_pub_exp),
        .rsa_pub_exp_bits (sb_pub_exp_bits),
        .rsa_modulus      (sb_modulus),
        .boot_allow       (sb_boot_allow),
        .boot_deny        (sb_boot_deny),
        .boot_busy        (sb_boot_busy),
        .boot_hash_out    (sb_boot_hash_out)
    );

    eeg_security_top #(
        .MAX_BLOCKS(16)
    ) u_sec_top (
        .clk                    (clk),
        .rst                    (rst),
        .encrypt_start          (sec_encrypt_start),
        .decrypt_start          (sec_decrypt_start),
        .aes_key                (sec_aes_key),
        .hmac_key               (sec_hmac_key),
        .hmac_key_len           (sec_hmac_key_len),
        .nonce_seed             (sec_nonce_seed),
        .nonce_increment        (sec_nonce_increment),
        .current_nonce          (sec_current_nonce),
        .eeg_data_valid         (sec_eeg_data_valid),
        .eeg_data_in            (sec_eeg_data_in),
        .eeg_data_last          (sec_eeg_data_last),
        .eeg_data_len           (sec_eeg_data_len),
        .metadata_valid         (sec_metadata_valid),
        .metadata_block         (sec_metadata_block),
        .metadata_len           (sec_metadata_len),
        .data_out               (sec_data_out),
        .data_out_valid         (sec_data_out_valid),
        .storage_nonce          (sec_storage_nonce),
        .storage_gcm_tag        (sec_storage_gcm_tag),
        .storage_hmac           (sec_storage_hmac),
        .storage_ready          (sec_storage_ready),
        .decrypt_nonce          (sec_decrypt_nonce),
        .decrypt_gcm_tag        (sec_decrypt_gcm_tag),
        .decrypt_hmac           (sec_decrypt_hmac),
        .auth_verified          (sec_auth_verified),
        .auth_failed            (sec_auth_failed),
        .hmac_check_ok          (sec_hmac_check_ok),
        .gcm_check_ok           (sec_gcm_check_ok),
        .busy                   (sec_busy),
        .done                   (sec_done),
        .error                  (sec_error),
        .chain_genesis          (sec_chain_genesis),
        .chain_init             (sec_chain_init),
        .chain_hash_out         (sec_chain_hash_out),
        .chain_entry_count      (sec_chain_entry_count),
        .chain_hash_valid       (sec_chain_hash_valid),
        .chain_verify_start     (sec_chain_verify_start),
        .chain_verify_prev_hash (sec_chain_verify_prev_hash),
        .chain_verify_log_data  (sec_chain_verify_log_data),
        .chain_verify_expected  (sec_chain_verify_expected),
        .chain_verify_ok        (sec_chain_verify_ok),
        .chain_verify_fail      (sec_chain_verify_fail),
        .boot_bitstream_block   (sec_boot_bitstream_block),
        .boot_bitstream_valid   (sec_boot_bitstream_valid),
        .boot_bitstream_last    (sec_boot_bitstream_last),
        .boot_bitstream_len     (sec_boot_bitstream_len),
        .boot_public_key_n      (sec_boot_public_key_n),
        .boot_signature         (sec_boot_signature),
        .boot_pub_exp           (sec_boot_pub_exp),
        .boot_pub_exp_bits      (sec_boot_pub_exp_bits),
        .boot_verify_start      (sec_boot_verify_start),
        .boot_allow             (sec_boot_allow),
        .boot_deny              (sec_boot_deny),
        .boot_busy              (sec_boot_busy),
        .boot_hash_out          (sec_boot_hash_out)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            cycle_count <= 0;
            output_count <= 0;
            sec_output_count <= 0;
            sec_last_data_out <= 128'h0;
        end else begin
            cycle_count <= cycle_count + 1;
            if (out_valid) begin
                if (first_output_cycle == -1) begin
                    first_output_cycle = cycle_count;
                    measured_latency = first_output_cycle - first_input_cycle;
                end
                output_history[output_count] = out_sample;
                output_count <= output_count + 1;
            end
            if (sec_data_out_valid) begin
                sec_last_data_out <= sec_data_out;
                sec_output_count <= sec_output_count + 1;
            end
        end
    end

    function logic [DATA_WIDTH-1:0] float_to_fixed(real value);
        int temp;
        temp = int'($floor(value * 256.0 + 0.5));
        return temp[DATA_WIDTH-1:0];
    endfunction

    task reset_all;
        begin
            rst                    = 1'b1;
            in_sample              = '0;
            in_valid               = 1'b0;
            first_input_cycle      = -1;
            first_output_cycle     = -1;
            measured_latency       = -1;
            sha_start              = 1'b0;
            sha_data_in            = 512'h0;
            sha_use_init           = 1'b0;
            sha_init_hash          = 256'h0;
            hmac_start             = 1'b0;
            hmac_key               = 512'h0;
            hmac_key_len           = 8'h0;
            hmac_key_is_hashed     = 1'b0;
            hmac_msg_data          = 512'h0;
            hmac_msg_len           = 64'h0;
            hmac_msg_valid         = 1'b0;
            hmac_msg_last          = 1'b0;
            hc_log_valid           = 1'b0;
            hc_log_data            = 256'h0;
            hc_genesis_hash        = 256'h0;
            hc_init_chain          = 1'b0;
            hc_verify_start        = 1'b0;
            hc_verify_prev_hash    = 256'h0;
            hc_verify_log_data     = 256'h0;
            hc_verify_expected     = 256'h0;
            sb_boot_start          = 1'b0;
            sb_bitstream_block     = 512'h0;
            sb_bitstream_valid     = 1'b0;
            sb_bitstream_last      = 1'b0;
            sb_bitstream_len       = 64'h0;
            sb_signature           = 2048'h0;
            sb_pub_exp             = 2048'h0;
            sb_pub_exp_bits        = 12'h0;
            sb_modulus             = 2048'h0;
            sec_encrypt_start      = 1'b0;
            sec_decrypt_start      = 1'b0;
            sec_aes_key            = 256'h0;
            sec_hmac_key           = 512'h0;
            sec_hmac_key_len       = 8'h0;
            sec_nonce_seed         = 96'h0;
            sec_nonce_increment    = 1'b0;
            sec_eeg_data_valid     = 1'b0;
            sec_eeg_data_in        = 128'h0;
            sec_eeg_data_last      = 1'b0;
            sec_eeg_data_len       = 64'h0;
            sec_metadata_valid     = 1'b0;
            sec_metadata_block     = 128'h0;
            sec_metadata_len       = 64'h0;
            sec_decrypt_nonce      = 96'h0;
            sec_decrypt_gcm_tag    = 128'h0;
            sec_decrypt_hmac       = 256'h0;
            sec_chain_genesis      = 256'h0;
            sec_chain_init         = 1'b0;
            sec_chain_verify_start = 1'b0;
            sec_chain_verify_prev_hash = 256'h0;
            sec_chain_verify_log_data  = 256'h0;
            sec_chain_verify_expected  = 256'h0;
            sec_boot_bitstream_block = 512'h0;
            sec_boot_bitstream_valid = 1'b0;
            sec_boot_bitstream_last  = 1'b0;
            sec_boot_bitstream_len   = 64'h0;
            sec_boot_public_key_n    = 2048'h0;
            sec_boot_signature       = 2048'h0;
            sec_boot_pub_exp         = 2048'h0;
            sec_boot_pub_exp_bits    = 12'h0;
            sec_boot_verify_start    = 1'b0;
            repeat (8) @(posedge clk);
            rst = 1'b0;
            repeat (4) @(posedge clk);
        end
    endtask

    task check_hash;
        input string test_name;
        input logic [255:0] got;
        input logic [255:0] expected;
        begin
            if (got === expected) begin
                $display("  [PASS] %s", test_name);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] %s", test_name);
                $display("         got      = 0x%064h", got);
                $display("         expected = 0x%064h", expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task send_sample;
        input real value;
        begin
            @(posedge clk);
            in_sample = float_to_fixed(value);
            in_valid  = 1'b1;
            if (first_input_cycle == -1)
                first_input_cycle = cycle_count + 1;
        end
    endtask

    task send_samples_stream;
        input integer num_samples;
        integer i;
        real val;
        begin
            for (i = 0; i < num_samples; i = i + 1) begin
                val = (i % 10) * 0.1;
                send_sample(val);
            end
            @(posedge clk);
            in_valid = 1'b0;
        end
    endtask

    task wait_for_top_outputs;
        input integer needed_outputs;
        input integer timeout_cycles;
        integer i;
        begin
            for (i = 0; i < timeout_cycles; i = i + 1) begin
                if (output_count >= needed_outputs)
                    return;
                @(posedge clk);
            end
            $display("  [FAIL] Timeout waiting for %0d ATCNet outputs", needed_outputs);
            fail_count = fail_count + 1;
        end
    endtask

    task collect_model_block;
        output logic [127:0] model_block;
        integer i;
        begin
            model_block = 128'h0;
            send_samples_stream(WINDOW_SIZE + 24);
            wait_for_top_outputs(8, 300);
            for (i = 0; i < 8; i = i + 1)
                model_block[127 - i*16 -: 16] = output_history[i];
        end
    endtask

    task test_top_basic_flow;
        begin
            $display("\n[TEST 1] ATCNet basic data flow");
            test_count = test_count + 1;
            reset_all();
            send_samples_stream(WINDOW_SIZE + 10);
            wait_for_top_outputs(1, 150);
            if (output_count > 0) begin
                $display("  [PASS] ATCNet produced %0d outputs", output_count);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] ATCNet produced no outputs");
                fail_count = fail_count + 1;
            end
        end
    endtask

    task test_sha256_abc;
        begin
            $display("\n[TEST 2] SHA-256 of abc");
            test_count = test_count + 1;
            reset_all();
            sha_data_in   = {32'h61626380, 416'h0, 64'h0000_0000_0000_0018};
            sha_use_init  = 1'b0;
            sha_start     = 1'b1;
            @(posedge clk);
            sha_start     = 1'b0;
            wait (sha_digest_valid);
            @(posedge clk);
            check_hash("SHA-256 abc", sha_digest, 256'hba7816bf8f01cfea414140de5dae2ec73b00361bbef0469049e182f4a848eefd);
        end
    endtask

    task test_hmac_tc1;
        begin
            $display("\n[TEST 3] HMAC-SHA256 RFC4231 TC1");
            test_count = test_count + 1;
            reset_all();
            hmac_key           = {160'h0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b, 352'h0};
            hmac_key_len       = 8'd20;
            hmac_key_is_hashed = 1'b0;
            hmac_msg_data      = {64'h4869205468657265, 448'h0};
            hmac_msg_len       = 64'd8;
            hmac_start = 1'b1;
            @(posedge clk);
            hmac_start = 1'b0;
            repeat (10) @(posedge clk);
            @(posedge clk);
            hmac_msg_valid = 1'b1;
            hmac_msg_last  = 1'b1;
            @(posedge clk);
            hmac_msg_valid = 1'b0;
            hmac_msg_last  = 1'b0;
            wait (hmac_valid);
            @(posedge clk);
            check_hash("HMAC RFC4231 TC1", hmac_out, 256'hb0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7);
        end
    endtask

    task test_hash_chain;
        logic [255:0] genesis;
        logic [255:0] entry_data;
        logic [255:0] expected_hash;
        integer timeout_cnt;
        begin
            $display("\n[TEST 4] SHA-256 hash chain append and verify");
            test_count = test_count + 1;
            reset_all();
            genesis    = 256'hCAFEBABEDEADBEEF00112233445566778899AABBCCDDEEFFFFEEDDCCBBAA9988;
            entry_data = 256'h000000010000000000000003DEADBEEFCAFEBABE11223344AABBCCDD00000080;
            hc_genesis_hash = genesis;
            hc_init_chain   = 1'b1;
            @(posedge clk);
            hc_init_chain   = 1'b0;
            hc_log_data     = entry_data;
            hc_log_valid    = 1'b1;
            @(posedge clk);
            hc_log_valid    = 1'b0;
            timeout_cnt = 0;
            while (!hc_hash_valid && timeout_cnt < 400) begin
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
            end
            if (!hc_hash_valid) begin
                $display("  [FAIL] Hash-chain append timed out");
                fail_count = fail_count + 1;
            end else begin
                expected_hash = hc_chain_hash;
                hc_verify_prev_hash = genesis;
                hc_verify_log_data  = entry_data;
                hc_verify_expected  = expected_hash;
                hc_verify_start     = 1'b1;
                @(posedge clk);
                hc_verify_start     = 1'b0;
                timeout_cnt = 0;
                while (!hc_verify_ok && !hc_verify_fail && timeout_cnt < 400) begin
                    @(posedge clk);
                    timeout_cnt = timeout_cnt + 1;
                end
                if (hc_verify_ok) begin
                    $display("  [PASS] Hash-chain verify succeeded");
                    pass_count = pass_count + 1;
                end else begin
                    $display("  [FAIL] Hash-chain verify failed");
                    fail_count = fail_count + 1;
                end
            end
        end
    endtask

    task test_secure_boot_flow;
        integer timeout_cnt;
        begin
            $display("\n[TEST 5] Secure-boot verification flow");
            test_count = test_count + 1;
            reset_all();
            sb_bitstream_block = {
                8'hAA, 8'hAA, 8'hAA, 8'hAA, 8'hAA, 8'hAA, 8'hAA, 8'hAA,
                8'hAA, 8'hAA, 8'hAA, 8'hAA, 8'hAA, 8'hAA, 8'hAA, 8'hAA,
                8'hAA, 8'hAA, 8'hAA, 8'hAA, 8'hAA, 8'hAA, 8'hAA, 8'hAA,
                8'hAA, 8'hAA, 8'hAA, 8'hAA, 8'hAA, 8'hAA, 8'hAA, 8'hAA,
                8'h80,
                {23{8'h00}},
                64'h0000_0000_0000_0100
            };  // 256+8+184+64 = 512 bits
            sb_bitstream_valid = 1'b1;
            sb_bitstream_last  = 1'b1;
            sb_bitstream_len   = 64'd32;
            sb_pub_exp         = 2048'h10001;
            sb_pub_exp_bits    = 12'd17;
            sb_modulus         = ~2048'h0;
            sb_signature       = 2048'h1;
            @(posedge clk);
            sb_boot_start = 1'b1;
            @(posedge clk);
            sb_boot_start = 1'b0;
            sb_bitstream_valid = 1'b0;
            sb_bitstream_last  = 1'b0;
            timeout_cnt = 0;
            while (!sb_boot_allow && !sb_boot_deny && timeout_cnt < 300000) begin
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
            end
            if (sb_boot_allow || sb_boot_deny) begin
                $display("  [PASS] Secure-boot flow completed (allow=%0b deny=%0b)", sb_boot_allow, sb_boot_deny);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] Secure-boot flow timed out");
                fail_count = fail_count + 1;
            end
        end
    endtask

    task test_atcnet_security_integration;
        logic [127:0] model_block;
        logic [127:0] encrypted_block;
        logic [95:0]  saved_nonce;
        logic [127:0] saved_gcm_tag;
        logic [255:0] saved_hmac;
        integer timeout_cnt;
        begin
            $display("\n[TEST 6] ATCNet output through integrated security flow");
            test_count = test_count + 1;
            reset_all();
            collect_model_block(model_block);
            sec_aes_key       = 256'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f;
            sec_hmac_key      = {256'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f, 256'h0};
            sec_hmac_key_len  = 8'd32;
            sec_nonce_seed    = 96'hAABBCCDDEEFF001122334455;
            sec_eeg_data_len  = 64'd128;
            sec_chain_genesis = 256'h1234567890abcdef00112233445566778899aabbccddeefffedcba0987654321;
            sec_chain_init    = 1'b1;
            @(posedge clk);
            sec_chain_init    = 1'b0;
            @(posedge clk);
            sec_encrypt_start = 1'b1;
            @(posedge clk);
            sec_encrypt_start = 1'b0;
            repeat (5) @(posedge clk);
            @(posedge clk);
            sec_eeg_data_valid = 1'b1;
            sec_eeg_data_in    = model_block;
            sec_eeg_data_last  = 1'b1;
            @(posedge clk);
            sec_eeg_data_valid = 1'b0;
            sec_eeg_data_last  = 1'b0;
            timeout_cnt = 0;
            while (!sec_storage_ready && timeout_cnt < 5000) begin
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
            end
            if (!sec_storage_ready) begin
                $display("  [FAIL] Encryption/storage phase timed out");
                fail_count = fail_count + 1;
                return;
            end
            encrypted_block = sec_last_data_out;
            saved_nonce     = sec_storage_nonce;
            saved_gcm_tag   = sec_storage_gcm_tag;
            saved_hmac      = sec_storage_hmac;
            reset_all();
            sec_aes_key        = 256'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f;
            sec_hmac_key       = {256'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f, 256'h0};
            sec_hmac_key_len   = 8'd32;
            sec_eeg_data_len   = 64'd128;
            sec_decrypt_nonce  = saved_nonce;
            sec_decrypt_gcm_tag= saved_gcm_tag;
            sec_decrypt_hmac   = saved_hmac;
            @(posedge clk);
            sec_decrypt_start = 1'b1;
            @(posedge clk);
            sec_decrypt_start = 1'b0;
            repeat (5) @(posedge clk);
            @(posedge clk);
            sec_eeg_data_valid = 1'b1;
            sec_eeg_data_in    = encrypted_block;
            sec_eeg_data_last  = 1'b1;
            @(posedge clk);
            sec_eeg_data_valid = 1'b0;
            sec_eeg_data_last  = 1'b0;
            timeout_cnt = 0;
            while (!sec_done && !sec_auth_failed && timeout_cnt < 5000) begin
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
            end
            if (sec_hmac_check_ok && sec_auth_verified && (sec_last_data_out === model_block)) begin
                $display("  [PASS] ATCNet -> security encrypt/decrypt flow verified");
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] Integrated security flow failed");
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        cycle_count = 0;
        output_count = 0;
        sec_output_count = 0;
        first_input_cycle = -1;
        first_output_cycle = -1;
        measured_latency = -1;
        $display("===========================================================");
        $display("Unified ATCNet + Security Testbench");
        $display("===========================================================");
        test_top_basic_flow();
        test_sha256_abc();
        test_hmac_tc1();
        test_hash_chain();
        test_secure_boot_flow();
        test_atcnet_security_integration();
        repeat (20) @(posedge clk);
        $display("\n===========================================================");
        $display("Summary");
        $display("===========================================================");
        $display("Tests   : %0d", test_count);
        $display("Passed  : %0d", pass_count);
        $display("Failed  : %0d", fail_count);
        $display("Cycles  : %0d", cycle_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d TEST(S) FAILED", fail_count);
        $finish;
    end

    initial begin
        #800_000_000;
        $display("[ERROR] Unified testbench timeout");
        $finish;
    end

    initial begin
        $dumpfile("top_tb.vcd");
        $dumpvars(0, top_tb);
    end

endmodule
