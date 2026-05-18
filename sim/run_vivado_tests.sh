#!/usr/bin/env bash
# =============================================================================
# run_vivado_tests.sh  —  DB-ATCNet (HaLT) Vivado Test Runner (Linux)
#
# Usage:
#   chmod +x sim/run_vivado_tests.sh        # first time only
#   ./sim/run_vivado_tests.sh [test_name]
#
# Available tests:
#   conv2d_temporal  - Bit-exact compare for Layer 1+2 (Conv2D temporal F1=16
#                      KE=64 padding='same' + BN folded into bias) against
#                      data/golden_q88/* — needs `scripts/q88_layer1.py`.
#   eca              - Bit-exact compare for ECA₁ (Conv1D 3-tap + sigmoid LUT)
#                      against data/golden_q88/stage_eca1_* — needs
#                      `scripts/gen_sigmoid_lut.py` and `scripts/q88_eca1.py`.
#
#   security    - Full security stack regression (SHA-256, HMAC, AES-GCM,
#                 hash chain, RSA secure boot, eeg_security_top).
#   aes         - AES-256-GCM standalone (NIST vectors).
#   hmac        - SHA-256 + HMAC + Hash Chain + RSA Secure Boot.
#
#   help        - Show this help.
# =============================================================================

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST=${1:-help}

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

show_help() {
    cat <<EOF

${CYAN}DB-ATCNet (HaLT) Vivado Test Runner${NC}
====================================

${YELLOW}Usage:${NC}
  ./sim/run_vivado_tests.sh [test_name]

${YELLOW}Available tests:${NC}
  conv2d_temporal - Layer 1+2 (Conv2D + folded BN) bit-exact regression.
  eca             - Layer 3 ECA₁ gate-compute (Conv1D + σ-LUT) bit-exact.
  gap             - Streaming GAP accumulator (reciprocal-multiply) bit-exact.
  gate_apply      - Per-channel gate multiplier bit-exact.
  dwise_a         - Layer 4: Branch A depthwise (1,5) D=2 + BN folded — bit-exact.
  security        - Full security stack (SHA/HMAC/AES/secure boot).
  aes             - AES-256-GCM standalone test.
  hmac            - SHA/HMAC/HashChain/RSA boot integration.
  help            - Show this message.

${YELLOW}Note:${NC} The Conv2D Layer-1 test reads data/golden_q88/stage_conv2d_*.hex.
       Regenerate those for the new HaLT shape (5x600) with:
           python3 scripts/q88_layer1.py
       (script will be updated for HaLT dims in a follow-up commit)

EOF
}

die() {
    echo -e "${RED}$1${NC}" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Layer 1: bit-exact regression of conv2d_temporal vs Q8.8 reference.
# ---------------------------------------------------------------------------
run_conv2d_temporal() {
    echo ""
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}Running Layer 1: Conv2D Temporal Bit-Exact Test${NC}"
    echo -e "${GREEN}================================================${NC}"
    cd "$PROJECT_ROOT" || die "Cannot cd to $PROJECT_ROOT"

    if [ ! -f data/golden_q88/stage_conv2d_input.hex ] || \
       [ ! -f data/golden_q88/stage_conv2d_weights.hex ] || \
       [ ! -f data/golden_q88/stage_conv2d_output.hex ]; then
        die "Q8.8 reference missing. Run: python3 scripts/q88_layer1.py"
    fi

    echo -e "${YELLOW}[1/3] Compiling...${NC}"
    xvlog --sv \
        rtl/conv/conv2d_temporal.sv \
        sim/conv2d_temporal_tb.sv || die "Compilation failed!"

    echo -e "${YELLOW}[2/3] Elaborating...${NC}"
    xelab conv2d_temporal_tb -debug typical || die "Elaboration failed!"

    echo -e "${YELLOW}[3/3] Simulating...${NC}"
    xsim conv2d_temporal_tb -runall

    echo -e "${GREEN}Layer 1 test complete!${NC}"
}

# ---------------------------------------------------------------------------
# Layer 3: ECA₁ gate-compute (Conv1D + sigmoid LUT).
# ---------------------------------------------------------------------------
run_eca() {
    echo ""
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}Running Layer 3: ECA₁ Bit-Exact Test${NC}"
    echo -e "${GREEN}================================================${NC}"
    cd "$PROJECT_ROOT" || die "Cannot cd to $PROJECT_ROOT"

    [ -f data/lut/sigmoid_q88.hex ] || die "missing data/lut/sigmoid_q88.hex — run: python3 scripts/gen_sigmoid_lut.py"
    [ -f data/golden_q88/stage_eca1_input.hex ] || die "missing ECA₁ refs — run: python3 scripts/q88_eca1.py"

    echo -e "${YELLOW}[1/3] Compiling...${NC}"
    xvlog --sv \
        rtl/attention/eca_attention.sv \
        sim/eca_attention_tb.sv || die "Compilation failed!"

    echo -e "${YELLOW}[2/3] Elaborating...${NC}"
    xelab eca_attention_tb -debug typical || die "Elaboration failed!"

    echo -e "${YELLOW}[3/3] Simulating...${NC}"
    xsim eca_attention_tb -runall

    echo -e "${GREEN}ECA₁ test complete!${NC}"
}

# ---------------------------------------------------------------------------
# Streaming GAP accumulator (reciprocal-multiply divide-by-N).
# ---------------------------------------------------------------------------
run_gap() {
    echo ""
    echo -e "${GREEN}Running GAP accumulator bit-exact test${NC}"
    cd "$PROJECT_ROOT" || die "Cannot cd to $PROJECT_ROOT"
    [ -f data/golden_q88/stage_conv2d_output.hex ] || die "missing Layer 1+2 output — run: python3 scripts/q88_layer1.py"
    [ -f data/golden_q88/stage_eca1_input.hex    ] || die "missing GAP reference — run: python3 scripts/q88_eca1.py"
    xvlog --sv rtl/attention/gap_accumulator.sv sim/gap_accumulator_tb.sv || die "Compilation failed!"
    xelab gap_accumulator_tb -debug typical || die "Elaboration failed!"
    xsim gap_accumulator_tb -runall
    echo -e "${GREEN}GAP accumulator test complete!${NC}"
}

# ---------------------------------------------------------------------------
# Per-channel gate-apply multiplier.
# ---------------------------------------------------------------------------
run_gate_apply() {
    echo ""
    echo -e "${GREEN}Running gate_apply bit-exact test${NC}"
    cd "$PROJECT_ROOT" || die "Cannot cd to $PROJECT_ROOT"
    [ -f data/golden_q88/stage_conv2d_output.hex ] || die "missing Layer 1+2 output — run: python3 scripts/q88_layer1.py"
    [ -f data/golden_q88/stage_eca1_gate.hex     ] || die "missing ECA₁ gate — run: python3 scripts/q88_eca1.py"
    [ -f data/golden_q88/stage_eca1_output.hex   ] || die "missing gated feature map — run: python3 scripts/q88_eca1.py"
    xvlog --sv rtl/attention/gate_apply.sv sim/gate_apply_tb.sv || die "Compilation failed!"
    xelab gate_apply_tb -debug typical || die "Elaboration failed!"
    xsim gate_apply_tb -runall
    echo -e "${GREEN}gate_apply test complete!${NC}"
}

# ---------------------------------------------------------------------------
# Layer 4: Branch A depthwise (1,5) D=2 + BN folded.
# ---------------------------------------------------------------------------
run_dwise_a() {
    echo ""
    echo -e "${GREEN}Running Layer 4 (Branch A depthwise + BN) bit-exact test${NC}"
    cd "$PROJECT_ROOT" || die "Cannot cd to $PROJECT_ROOT"
    [ -f data/golden_q88/stage_branchA_dwise_input.hex   ] || die "missing refs — run: python3 scripts/q88_layer4.py"
    [ -f data/golden_q88/stage_branchA_dwise_weights.hex ] || die "missing refs — run: python3 scripts/q88_layer4.py"
    [ -f data/golden_q88/stage_branchA_dwise_bias.hex    ] || die "missing refs — run: python3 scripts/q88_layer4.py"
    [ -f data/golden_q88/stage_branchA_dwise_output.hex  ] || die "missing refs — run: python3 scripts/q88_layer4.py"
    xvlog --sv rtl/conv/depthwise_spatial.sv sim/depthwise_spatial_tb.sv || die "Compilation failed!"
    xelab depthwise_spatial_tb -debug typical || die "Elaboration failed!"
    xsim depthwise_spatial_tb -runall
    echo -e "${GREEN}Branch A depthwise test complete!${NC}"
}

# ---------------------------------------------------------------------------
# Security stack — unchanged from original, just kept here.
# ---------------------------------------------------------------------------
run_security() {
    echo ""
    echo -e "${GREEN}Running ALL Security Algorithms${NC}"
    cd "$PROJECT_ROOT" || die "Cannot cd to $PROJECT_ROOT"

    # Part 1: AES-256-GCM standalone
    echo -e "${YELLOW}-- AES-256-GCM standalone --${NC}"
    xvlog --sv \
        rtl/security/gcm_ghash.sv \
        rtl/security/aes_256_core.sv \
        rtl/security/aes_256_gcm.sv \
        sim/aes_256_gcm_tb.sv || die "AES compilation failed!"
    xelab aes_256_gcm_tb -debug typical || die "AES elaboration failed!"
    xsim aes_256_gcm_tb -runall

    # Part 2: full security stack
    echo -e "${YELLOW}-- Full security stack --${NC}"
    xvlog --sv \
        rtl/security/sha256_core.sv \
        rtl/security/sha256_hash_chain.sv \
        rtl/security/hmac_sha256.sv \
        rtl/security/gcm_ghash.sv \
        rtl/security/aes_256_core.sv \
        rtl/security/aes_256_gcm.sv \
        rtl/security/rsa2048_core.sv \
        rtl/security/secure_boot.sv \
        rtl/security/eeg_security_top.sv \
        sim/hmac_sha256_tb.sv || die "Security compilation failed!"
    xelab hmac_sha256_tb -debug typical || die "Security elaboration failed!"
    xsim hmac_sha256_tb -runall

    echo -e "${GREEN}Security stack complete!${NC}"
}

run_hmac() {
    cd "$PROJECT_ROOT" || die "Cannot cd to $PROJECT_ROOT"
    xvlog --sv \
        rtl/security/sha256_core.sv \
        rtl/security/sha256_hash_chain.sv \
        rtl/security/hmac_sha256.sv \
        rtl/security/gcm_ghash.sv \
        rtl/security/aes_256_core.sv \
        rtl/security/aes_256_gcm.sv \
        rtl/security/rsa2048_core.sv \
        rtl/security/secure_boot.sv \
        rtl/security/eeg_security_top.sv \
        sim/hmac_sha256_tb.sv || die "Compilation failed!"
    xelab hmac_sha256_tb -debug typical || die "Elaboration failed!"
    xsim hmac_sha256_tb -runall
}

run_aes() {
    cd "$PROJECT_ROOT" || die "Cannot cd to $PROJECT_ROOT"
    xvlog --sv \
        rtl/security/gcm_ghash.sv \
        rtl/security/aes_256_core.sv \
        rtl/security/aes_256_gcm.sv \
        sim/aes_256_gcm_tb.sv || die "Compilation failed!"
    xelab aes_256_gcm_tb -debug typical || die "Elaboration failed!"
    xsim aes_256_gcm_tb -runall
}

case "$TEST" in
    conv2d_temporal) run_conv2d_temporal ;;
    eca)             run_eca ;;
    gap)             run_gap ;;
    gate_apply)      run_gate_apply ;;
    dwise_a)         run_dwise_a ;;
    security)        run_security ;;
    hmac)            run_hmac ;;
    aes)             run_aes ;;
    help|*)          show_help ;;
esac
