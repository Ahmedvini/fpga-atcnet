#!/bin/bash

yosys -p "
read_verilog -sv \
rtl/top.sv \
rtl/attention/temporal_multihead_attention.sv \
rtl/conv/channel_scale.sv \
rtl/conv/dual_branch_conv.sv \
rtl/conv/Spatial_conv.sv \
rtl/conv/temporal_conv.sv \
rtl/fusion/temporal_fusion.sv \
rtl/window/window_gen.sv \
rtl/window/window_reader.sv \
rtl/security/aes_256_core.sv \
rtl/security/aes_256_gcm.sv \
rtl/security/eeg_data_encryptor.sv \
rtl/security/eeg_dataset_config.sv \
rtl/security/eeg_security_top.sv \
rtl/security/gcm_ghash.sv \
rtl/security/hmac_demo_top.sv \
rtl/security/hmac_sha256.sv \
rtl/security/rsa2048_core.sv \
rtl/security/secure_boot.sv \
rtl/security/sha256_core.sv \
rtl/security/sha256_hash_chain.sv

hierarchy -check -top top

proc
opt

stat
"
