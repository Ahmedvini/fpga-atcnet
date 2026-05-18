#!/usr/bin/env bash
#
# Elaboration / parse-check for the DB-ATCNet RTL (HaLT variant, 5-of-19
# channels, 2-class output, subject-dependent weights).
#
# Primary tool: Vivado (xvlog + xelab). The design uses SystemVerilog
# constructs (unpacked-array parameters, '{default:0} initializers, multi-
# dimensional unpacked arrays) that Yosys 0.33's built-in SV frontend does
# not support without sv2v.
#
# Usage:   ./build.sh [top_module]
# Default top: conv2d_temporal      (Layer 1 standalone — only built so far)

set -euo pipefail

TOP="${1:-conv2d_temporal}"

# Model RTL (HaLT pipeline). Add new modules here as they are built.
MODEL_RTL=(
  rtl/attention/eca_attention.sv
  rtl/conv/conv2d_temporal.sv
  rtl/window/eeg_channel_adapter.sv
)

# Security stack — separate from the AI pipeline, built alongside.
SEC_RTL=(
  rtl/security/aes_256_core.sv
  rtl/security/aes_256_gcm.sv
  rtl/security/eeg_data_encryptor.sv
  rtl/security/eeg_dataset_config.sv
  rtl/security/eeg_security_top.sv
  rtl/security/gcm_ghash.sv
  rtl/security/hmac_demo_top.sv
  rtl/security/hmac_sha256.sv
  rtl/security/rsa2048_core.sv
  rtl/security/secure_boot.sv
  rtl/security/sha256_core.sv
  rtl/security/sha256_hash_chain.sv
)

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="$(mktemp -d -t atcnet_build.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT

ABS_MODEL=( "${MODEL_RTL[@]/#/$REPO_ROOT/}" )
ABS_SEC=(   "${SEC_RTL[@]/#/$REPO_ROOT/}" )

echo "[build] xvlog parse-check (model + security)..."
( cd "$WORK_DIR" && xvlog -sv "${ABS_MODEL[@]}" "${ABS_SEC[@]}" > xvlog.log 2>&1 ) || {
  echo "[build] xvlog FAILED. Log:"; cat "$WORK_DIR/xvlog.log"; exit 1; }
grep -E "ERROR|WARNING" "$WORK_DIR/xvlog.log" || echo "[build] xvlog: clean"

echo "[build] xelab elaborate top='$TOP'..."
( cd "$WORK_DIR" && xelab "work.$TOP" > xelab.log 2>&1 ) || {
  if grep -q "Failed to link" "$WORK_DIR/xelab.log"; then
    echo "[build] note: xelab compiled RTL OK; final link to xsim needs libc-dev installed."
    grep -E "Compiling module|ERROR" "$WORK_DIR/xelab.log" | head -40
  else
    cat "$WORK_DIR/xelab.log"; exit 1
  fi
}

if command -v sv2v >/dev/null 2>&1; then
  echo "[build] sv2v + yosys stat (optional area estimate)..."
  SV2V_OUT="$WORK_DIR/atcnet_v2005.v"
  sv2v "${MODEL_RTL[@]}" > "$SV2V_OUT"
  yosys -q -p "read_verilog '$SV2V_OUT'; hierarchy -check -top $TOP; proc; opt; stat" \
    || echo "[build] yosys stat pass returned non-zero (informational only)"
else
  echo "[build] (sv2v not installed, skipping yosys stat pass)"
fi

echo "[build] done."
