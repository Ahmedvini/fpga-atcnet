#!/usr/bin/env bash
# =============================================================================
# run_vivado_tests.sh  —  ATCNet Vivado Test Runner (Linux)
#
# Usage:
#   chmod +x sim/run_vivado_tests.sh        # first time only
#   ./sim/run_vivado_tests.sh [test_name]
#
# Available tests:
#   hmac     — All security algorithms (SHA-256, HMAC, AES-GCM, Hash Chain,
#               RSA Secure Boot, eeg_security_top integration)  ← run this first
#   aes      — AES-256-GCM standalone test
#   temporal — Temporal convolution unit test
#   top      — Top-level integration test
#   all      — All DSP/RTL modules
#   help     — Show this help
# =============================================================================

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST=${1:-help}

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

show_help() {
    echo ""
    echo -e "${CYAN}ATCNet Vivado Test Runner (Linux)${NC}"
    echo "================================="
    echo ""
    echo -e "${YELLOW}Usage:${NC}"
    echo "  ./sim/run_vivado_tests.sh [test_name]"
    echo ""
    echo -e "${YELLOW}Available Tests:${NC}"
    echo "  security - ALL security algorithms (full combined run) ← use this"
    echo "  hmac     - SHA-256 + HMAC + Hash Chain + RSA Secure Boot + integration"
    echo "  aes      - AES-256-GCM standalone test"
    echo "  temporal - Temporal convolution unit test"
    echo "  top      - Top-level integration test"
    echo "  all      - All DSP/RTL modules"
    echo "  help     - Show this message"
    echo ""
}

die() {
    echo -e "${RED}$1${NC}" >&2
    exit 1
}

run_security() {
    echo ""
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}Running ALL Security Algorithms${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo ""
    echo "Algorithms covered:"
    echo "  [1] SHA-256 core          (FIPS 180-4 test vectors)"
    echo "  [2] HMAC-SHA-256          (RFC 4231 test vectors)"
    echo "  [3] AES-256-GCM           (NIST standalone vectors)"
    echo "  [4] AES-256-GCM           (integration with HMAC)"
    echo "  [5] SHA-256 Hash Chain    (tamper-evident audit log)"
    echo "  [6] RSA-2048 Secure Boot  (bitstream authentication)"
    echo "  [7] eeg_security_top      (all algorithms integrated)"
    echo ""

    cd "$PROJECT_ROOT" || die "Cannot cd to $PROJECT_ROOT"

    # ── Part 1: AES-256-GCM standalone (NIST vectors) ──────────────────
    echo -e "${YELLOW}── Part 1/2: AES-256-GCM standalone ──${NC}"
    echo -e "${YELLOW}[1/3] Compiling...${NC}"
    xvlog --sv \
        rtl/security/gcm_ghash.sv \
        rtl/security/aes_256_core.sv \
        rtl/security/aes_256_gcm.sv \
        sim/aes_256_gcm_tb.sv || die "AES compilation failed!"

    echo -e "${YELLOW}[2/3] Elaborating...${NC}"
    xelab aes_256_gcm_tb -debug typical || die "AES elaboration failed!"

    echo -e "${YELLOW}[3/3] Simulating...${NC}"
    xsim aes_256_gcm_tb -runall

    echo ""

    # ── Part 2: Full security stack (all remaining algorithms) ──────────
    echo -e "${YELLOW}── Part 2/2: Full security stack ──${NC}"
    echo -e "${YELLOW}[1/3] Compiling...${NC}"
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

    echo -e "${YELLOW}[2/3] Elaborating...${NC}"
    xelab hmac_sha256_tb -debug typical || die "Security elaboration failed!"

    echo -e "${YELLOW}[3/3] Simulating...${NC}"
    xsim hmac_sha256_tb -runall

    echo ""
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}All security algorithms simulation complete!${NC}"
    echo -e "${GREEN}================================================${NC}"
}

run_hmac() {
    echo ""
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}Running Full Security Test Suite${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo ""
    cd "$PROJECT_ROOT" || die "Cannot cd to $PROJECT_ROOT"

    echo -e "${YELLOW}[1/3] Compiling RTL and testbench...${NC}"
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

    echo -e "${YELLOW}[2/3] Elaborating design...${NC}"
    xelab hmac_sha256_tb -debug typical || die "Elaboration failed!"

    echo -e "${YELLOW}[3/3] Running simulation...${NC}"
    xsim hmac_sha256_tb -runall

    echo ""
    echo -e "${GREEN}Security test complete!${NC}"
}

run_aes() {
    echo ""
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}Running AES-256-GCM Standalone Test${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo ""
    cd "$PROJECT_ROOT" || die "Cannot cd to $PROJECT_ROOT"

    echo -e "${YELLOW}[1/3] Compiling...${NC}"
    xvlog --sv \
        rtl/security/gcm_ghash.sv \
        rtl/security/aes_256_core.sv \
        rtl/security/aes_256_gcm.sv \
        sim/aes_256_gcm_tb.sv || die "Compilation failed!"

    echo -e "${YELLOW}[2/3] Elaborating...${NC}"
    xelab aes_256_gcm_tb -debug typical || die "Elaboration failed!"

    echo -e "${YELLOW}[3/3] Simulating...${NC}"
    xsim aes_256_gcm_tb -runall

    echo ""
    echo -e "${GREEN}AES test complete!${NC}"
}

run_temporal() {
    echo ""
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}Running Temporal Conv Unit Test${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo ""
    cd "$PROJECT_ROOT" || die "Cannot cd to $PROJECT_ROOT"

    echo -e "${YELLOW}[1/3] Compiling...${NC}"
    xvlog --sv \
        rtl/conv/temporal_conv.sv \
        sim/temporal_conv_tb.sv || die "Compilation failed!"

    echo -e "${YELLOW}[2/3] Elaborating...${NC}"
    xelab temporal_conv_tb -debug typical || die "Elaboration failed!"

    echo -e "${YELLOW}[3/3] Simulating...${NC}"
    xsim temporal_conv_tb -runall

    echo ""
    echo -e "${GREEN}Temporal test complete!${NC}"
}

run_top() {
    echo ""
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}Running Top-Level Integration Test${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo ""
    cd "$PROJECT_ROOT" || die "Cannot cd to $PROJECT_ROOT"

    echo -e "${YELLOW}[1/3] Compiling...${NC}"
    xvlog --sv \
        rtl/conv/temporal_conv.sv \
        rtl/conv/dual_branch_conv.sv \
        rtl/conv/channel_scale.sv \
        rtl/window/window_gen.sv \
        rtl/window/window_reader.sv \
        rtl/top.sv \
        sim/top_tb.sv || die "Compilation failed!"

    echo -e "${YELLOW}[2/3] Elaborating...${NC}"
    xelab top_tb -debug typical || die "Elaboration failed!"

    echo -e "${YELLOW}[3/3] Simulating...${NC}"
    xsim top_tb -runall

    echo ""
    echo -e "${GREEN}Top test complete!${NC}"
}

run_all() {
    echo ""
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}Running All DSP/RTL Modules Test${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo ""
    cd "$PROJECT_ROOT" || die "Cannot cd to $PROJECT_ROOT"

    echo -e "${YELLOW}[1/3] Compiling...${NC}"
    xvlog --sv \
        rtl/conv/temporal_conv.sv \
        rtl/conv/dual_branch_conv.sv \
        rtl/conv/channel_scale.sv \
        rtl/window/window_gen.sv \
        rtl/window/window_reader.sv \
        rtl/fusion/temporal_fusion.sv \
        rtl/attention/temporal_multihead_attention.sv \
        sim/all_modules_tb.sv || die "Compilation failed!"

    echo -e "${YELLOW}[2/3] Elaborating...${NC}"
    xelab all_modules_tb -debug typical || die "Elaboration failed!"

    echo -e "${YELLOW}[3/3] Simulating...${NC}"
    xsim all_modules_tb -runall

    echo ""
    echo -e "${GREEN}All-modules test complete!${NC}"
}

case "$TEST" in
    security) run_security ;;
    hmac)     run_hmac ;;
    aes)      run_aes ;;
    temporal) run_temporal ;;
    top)      run_top ;;
    all)      run_all ;;
    help|*)   show_help ;;
esac
