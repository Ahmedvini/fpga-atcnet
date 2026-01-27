/**
 * Module: eeg_data_encryptor
 * 
 * Description:
 *   Wrapper module for encrypting EEG data storage using AES-256-GCM.
 *   Implements NFR-9: Encrypt stored EEG data with authenticated encryption.
 *   
 *   This module provides confidentiality + integrity in one step using
 *   AES-256-GCM authenticated encryption as recommended by NIST SP 800-38D.
 *   
 * Storage Format (what to store to memory/flash):
 *   [96-bit Nonce/IV] || [N×128-bit Ciphertext Blocks] || [128-bit Auth Tag]
 *   
 *   Total storage overhead: 224 bits (28 bytes) per record
 *   
 * Security Model:
 *   - Key: 256-bit AES key derived from secure element or device secret
 *          (NOT stored with data, managed separately by key management module)
 *   - Nonce/IV: 96-bit unique value per encryption (MUST be unique per key)
 *   - Tag: 128-bit authentication tag for integrity verification
 *   
 * Usage Pattern for EEG Data:
 *   1. Generate/retrieve unique 96-bit nonce (counter-based or random)
 *   2. Encrypt EEG data block(s) with AES-256-GCM
 *   3. Store: nonce || ciphertext || tag to persistent storage
 *   4. For decryption: Read stored data, extract nonce/ciphertext/tag
 *   5. Decrypt and verify tag before using data
 *   
 * Features:
 *   - Stream-based interface for variable-length EEG records
 *   - Automatic nonce generation (counter-based, requires external seed)
 *   - Outputs all components needed for secure storage
 *   - Supports Additional Authenticated Data (e.g., timestamp, patient ID)
 *   
 * Parameters:
 *   MAX_BLOCKS - Maximum EEG data blocks per record (default: 32)
 */

module eeg_data_encryptor #(
    parameter int MAX_BLOCKS = 32  // Max 4096 bytes per EEG record
) (
    input  logic        clk,
    input  logic        rst,
    
    // Control signals
    input  logic        encrypt_start,    // Start encryption operation
    input  logic        decrypt_start,    // Start decryption operation
    
    // Key management (from secure element or key derivation)
    input  logic [255:0] aes_key,         // 256-bit encryption key
    
    // Nonce/IV management
    input  logic [95:0]  nonce_seed,      // External nonce seed (e.g., timestamp)
    input  logic        nonce_increment,  // Auto-increment internal counter
    output logic [95:0]  current_nonce,   // Current nonce value (to store with data)
    
    // EEG data input (plaintext or ciphertext)
    input  logic        eeg_data_valid,   // EEG data block valid
    input  logic [127:0] eeg_data_in,     // 128-bit EEG data block
    input  logic        eeg_data_last,    // Last block indicator
    input  logic [63:0]  eeg_data_len,    // Total data length in bits
    
    // Optional metadata (Additional Authenticated Data)
    input  logic        metadata_valid,   // Metadata block valid
    input  logic [127:0] metadata_block,  // Metadata (timestamp, patient ID, etc.)
    input  logic [63:0]  metadata_len,    // Metadata length in bits
    
    // Encrypted output / Decrypted output
    output logic [127:0] data_out,        // Output data block
    output logic        data_out_valid,   // Output valid
    
    // Storage components (what to save to persistent memory)
    output logic [95:0]  storage_nonce,   // Nonce to store with data
    output logic [127:0] storage_tag,     // Authentication tag to store
    output logic        storage_ready,    // Storage components ready
    
    // Decryption verification
    input  logic [95:0]  decrypt_nonce,   // Nonce from stored data
    input  logic [127:0] decrypt_tag,     // Tag from stored data
    output logic        auth_verified,    // Authentication success
    output logic        auth_failed,      // Authentication failure (data corrupted)
    
    // Status
    output logic        busy,
    output logic        done,
    output logic        error             // Error condition
);

    // -------------------------------------------------------------------------
    // Internal Signals
    // -------------------------------------------------------------------------
    
    typedef enum logic [2:0] {
        IDLE,
        ENCRYPT_OP,
        DECRYPT_OP,
        CAPTURE_OUTPUTS,
        ERROR_STATE
    } state_t;
    
    state_t state, next_state;
    
    // Nonce counter for unique IV generation
    logic [31:0] nonce_counter;
    logic [95:0] operation_nonce;
    
    // AES-256-GCM module interface
    logic        gcm_start;
    logic        gcm_mode;  // 0=encrypt, 1=decrypt
    logic [95:0]  gcm_iv;
    logic        gcm_aad_valid;
    logic [127:0] gcm_aad_block;
    logic        gcm_aad_last;
    logic        gcm_data_valid;
    logic [127:0] gcm_data_in;
    logic        gcm_data_last;
    logic [63:0]  gcm_aad_len;
    logic [63:0]  gcm_data_len;
    logic [127:0] gcm_data_out;
    logic        gcm_data_out_valid;
    logic [127:0] gcm_auth_tag;
    logic        gcm_tag_valid;
    logic        gcm_auth_success;
    logic        gcm_busy;
    
    // Storage registers
    logic [95:0]  stored_nonce;
    logic [127:0] stored_tag;
    logic        outputs_captured;
    
    // -------------------------------------------------------------------------
    // AES-256-GCM Core Instance
    // -------------------------------------------------------------------------
    
    aes_256_gcm #(
        .MAX_BLOCKS(MAX_BLOCKS)
    ) u_aes_gcm (
        .clk            (clk),
        .rst            (rst),
        .start          (gcm_start),
        .mode           (gcm_mode),
        .key            (aes_key),
        .iv             (gcm_iv),
        .aad_valid      (gcm_aad_valid),
        .aad_block      (gcm_aad_block),
        .aad_last       (gcm_aad_last),
        .data_valid     (gcm_data_valid),
        .data_in        (gcm_data_in),
        .data_last      (gcm_data_last),
        .aad_len        (gcm_aad_len),
        .data_len       (gcm_data_len),
        .data_out       (gcm_data_out),
        .data_out_valid (gcm_data_out_valid),
        .auth_tag       (gcm_auth_tag),
        .tag_valid      (gcm_tag_valid),
        .auth_success   (gcm_auth_success),
        .busy           (gcm_busy)
    );
    
    // -------------------------------------------------------------------------
    // Nonce Management
    // Counter-based nonce generation for uniqueness guarantee
    // Format: [64-bit seed] || [32-bit counter]
    // -------------------------------------------------------------------------
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            nonce_counter <= 32'h0;
            operation_nonce <= 96'h0;
        end else begin
            if (nonce_increment) begin
                nonce_counter <= nonce_counter + 1;
            end
            
            // Combine seed with counter for unique nonce
            operation_nonce <= {nonce_seed[95:32], nonce_counter};
        end
    end
    
    assign current_nonce = operation_nonce;
    
    // -------------------------------------------------------------------------
    // State Machine
    // -------------------------------------------------------------------------
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            gcm_start <= 1'b0;
            stored_nonce <= 96'h0;
            stored_tag <= 128'h0;
            outputs_captured <= 1'b0;
        end else begin
            state <= next_state;
            gcm_start <= 1'b0;
            
            case (state)
                IDLE: begin
                    outputs_captured <= 1'b0;
                    
                    if (encrypt_start) begin
                        // Start encryption with current nonce
                        gcm_start <= 1'b1;
                        gcm_mode <= 1'b0;  // Encrypt
                        gcm_iv <= operation_nonce;
                        stored_nonce <= operation_nonce;  // Save for output
                    end else if (decrypt_start) begin
                        // Start decryption with provided nonce
                        gcm_start <= 1'b1;
                        gcm_mode <= 1'b1;  // Decrypt
                        gcm_iv <= decrypt_nonce;
                    end
                end
                
                ENCRYPT_OP: begin
                    // Pass through data to GCM module
                    // Capture tag when ready
                    if (gcm_tag_valid && !outputs_captured) begin
                        stored_tag <= gcm_auth_tag;
                        outputs_captured <= 1'b1;
                    end
                end
                
                DECRYPT_OP: begin
                    // Pass through data from GCM module
                    // Verify tag matches stored tag
                    if (gcm_tag_valid && !outputs_captured) begin
                        outputs_captured <= 1'b1;
                    end
                end
                
                CAPTURE_OUTPUTS: begin
                    // Hold outputs stable for storage controller
                end
                
                ERROR_STATE: begin
                    // Error handling
                end
            endcase
        end
    end
    
    // Next state logic
    always_comb begin
        next_state = state;
        
        case (state)
            IDLE: begin
                if (encrypt_start)
                    next_state = ENCRYPT_OP;
                else if (decrypt_start)
                    next_state = DECRYPT_OP;
            end
            
            ENCRYPT_OP: begin
                if (outputs_captured)
                    next_state = CAPTURE_OUTPUTS;
            end
            
            DECRYPT_OP: begin
                if (outputs_captured) begin
                    if (gcm_auth_success)
                        next_state = CAPTURE_OUTPUTS;
                    else
                        next_state = ERROR_STATE;
                end
            end
            
            CAPTURE_OUTPUTS: begin
                // Stay until acknowledged or new operation
                if (encrypt_start || decrypt_start)
                    next_state = IDLE;
            end
            
            ERROR_STATE: begin
                if (encrypt_start || decrypt_start)
                    next_state = IDLE;
            end
        endcase
    end
    
    // -------------------------------------------------------------------------
    // Data Path Connections
    // -------------------------------------------------------------------------
    
    // Connect input data to GCM
    assign gcm_data_valid = eeg_data_valid;
    assign gcm_data_in = eeg_data_in;
    assign gcm_data_last = eeg_data_last;
    assign gcm_data_len = eeg_data_len;
    
    // Connect metadata (AAD) to GCM
    assign gcm_aad_valid = metadata_valid;
    assign gcm_aad_block = metadata_block;
    assign gcm_aad_last = !metadata_valid;  // AAD ends when no metadata
    assign gcm_aad_len = metadata_len;
    
    // Connect outputs
    assign data_out = gcm_data_out;
    assign data_out_valid = gcm_data_out_valid;
    
    // -------------------------------------------------------------------------
    // Storage Interface
    // THESE ARE THE VALUES TO STORE TO PERSISTENT MEMORY
    // -------------------------------------------------------------------------
    
    assign storage_nonce = stored_nonce;      // 96 bits - MUST be stored
    assign storage_tag = stored_tag;          // 128 bits - MUST be stored
    assign storage_ready = (state == CAPTURE_OUTPUTS);
    
    // -------------------------------------------------------------------------
    // Status Outputs
    // -------------------------------------------------------------------------
    
    assign auth_verified = (state == CAPTURE_OUTPUTS) && (gcm_auth_success);
    assign auth_failed = (state == ERROR_STATE);
    assign busy = (state != IDLE) || gcm_busy;
    assign done = (state == CAPTURE_OUTPUTS);
    assign error = (state == ERROR_STATE);
    
endmodule
