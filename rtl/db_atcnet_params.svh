// =============================================================================
// db_atcnet_params.svh
//
// Central parameter header for DB-ATCNet on PhysioNet, derived from the
// shapes observed in `physionet subject independent .h5` (Keras 3 weights).
//
// Shapes recovered from the checkpoint:
//   - conv2d           (64, 1, 1, 16)   -> 1D temporal conv, KE=64, F1=16
//   - depthwise_conv2d (1, 64, 16, 2)   -> spatial depthwise across 64 EEG ch, D=2
//   - depthwise_conv2d_1 (1, 64, 16, 4) -> second branch, D=4 (dual-branch)
//   - dense / dense_1  (16,2) / (2,16)  -> SE channel-attention, ratio=8
//   - conv1d_*         (4, 32, 32) x 20 -> TCN: 5 windows x 2 blocks x 2 layers
//   - dense_2/14..18   (32,4)           -> per-window classifier, 4 classes
//   - depthwise/spatial conv2d_2/3      (16,1,32,32) / (16,1,64,32)
//
// All hyperparameters are localparam-friendly defaults; downstream modules
// override per instance.
// =============================================================================

`ifndef DB_ATCNET_PARAMS_SVH
`define DB_ATCNET_PARAMS_SVH

package db_atcnet_pkg;

    // -------------------------------------------------------------------------
    // Fixed-point format (signed Q(I).(FRAC_BITS))
    // -------------------------------------------------------------------------
    localparam int DATA_WIDTH    = 16;
    localparam int COEF_WIDTH    = 16;
    localparam int ACC_WIDTH     = 48;
    localparam int FRAC_BITS     = 8;   // Q8.8 throughout

    // -------------------------------------------------------------------------
    // Dataset shape (PhysioNet MI, subject-independent .h5)
    // -------------------------------------------------------------------------
    localparam int NUM_EEG_CH    = 64;
    localparam int SAMPLE_RATE   = 160;     // Hz
    localparam int TRIAL_SAMPLES = 640;     // 4 seconds @ 160 Hz
    localparam int NUM_CLASSES   = 4;

    // -------------------------------------------------------------------------
    // Hardware front-end: 3 EEG inputs mapped into the 64-channel array
    //
    // The trained .h5 expects 64 electrodes. We feed only 3 (C3/Cz/C4) into
    // their PhysioNet/BCI2000 10-10 indices; the other 61 are tied to 0.
    // Vivado will constant-propagate the dead multiplies in synthesis.
    //
    //   PhysioNet idx -> 10-10 name (subset relevant to motor imagery)
    //     8  -> C3   (left  motor cortex)
    //    10  -> Cz   (midline)
    //    12  -> C4   (right motor cortex)
    // -------------------------------------------------------------------------
    localparam int NUM_INPUT_CH  = 3;
    localparam int INPUT_IDX_C3  = 8;
    localparam int INPUT_IDX_CZ  = 10;
    localparam int INPUT_IDX_C4  = 12;

    // -------------------------------------------------------------------------
    // Block 1: Attention Dual-branch Conv
    // -------------------------------------------------------------------------
    localparam int F1            = 16;      // initial temporal filters
    localparam int KE            = 64;      // temporal kernel length
    localparam int D_BRANCH_A    = 2;       // depth multiplier, branch A
    localparam int D_BRANCH_B    = 4;       // depth multiplier, branch B
    localparam int F2_A          = F1 * D_BRANCH_A;  // 32
    localparam int F2_B          = F1 * D_BRANCH_B;  // 64
    localparam int F2            = 32;      // channel count after merge

    // Channel Attention (SE-block)
    localparam int SE_RATIO      = 8;
    localparam int SE_HIDDEN     = F1 / SE_RATIO;    // 2

    // -------------------------------------------------------------------------
    // Sliding Window + ATC branches
    // -------------------------------------------------------------------------
    localparam int NUM_WINDOWS   = 5;
    localparam int WINDOW_SIZE   = 32;      // legacy compat; recompute as TRIAL_SAMPLES/NUM_WINDOWS once temporal stride is fixed

    // -------------------------------------------------------------------------
    // TCN (per ATC branch)
    // -------------------------------------------------------------------------
    localparam int TCN_DEPTH     = 2;       // residual blocks per branch
    localparam int TCN_LAYERS    = 2;       // conv layers per block
    localparam int TCN_KSIZE     = 4;
    localparam int TCN_DIM       = 32;

    // -------------------------------------------------------------------------
    // MHA (paper) / channel-energy gate (current RTL approx)
    // -------------------------------------------------------------------------
    localparam int NUM_HEADS     = 2;       // start small; portable across Z-7020 / ZU3
    localparam int ATTN_SHIFT    = 4;

endpackage : db_atcnet_pkg

`endif // DB_ATCNET_PARAMS_SVH
