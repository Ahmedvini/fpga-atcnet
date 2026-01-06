# ATCNet Testbench Suite - Vivado Compatible

## 📋 Overview

Complete verification suite for FPGA ATCNet implementation, fully compatible with **Vivado Simulator (xsim)**.

**Test Coverage:** 20+ test cases across 8 modules

---

## 🧪 Testbenches

### 1. **temporal_conv_tb.sv** - Unit Test
Tests the `temporal_conv.sv` FIR filter module

**Test Cases (6):**
- ✅ Impulse Response
- ✅ DC Response (Constant Input)
- ✅ Ramp Response (Linearity Test)
- ✅ Zero Input Handling
- ✅ Latency Measurement (2 cycles)
- ✅ Streaming with Valid Gaps

**Quick Run:**
```powershell
.\run_vivado_tests.ps1 temporal
```

---

### 2. **top_tb.sv** - Integration Test
Tests the complete ATCNet pipeline

**Pipeline:**
```
Stream Input → Window Gen → Window Reader → Dual Branch Conv → Channel Scale → Output
```

**Test Cases (6):**
- ✅ End-to-End Data Flow
- ✅ Pipeline Latency (WINDOW_SIZE + 5 cycles)
- ✅ Valid Signal Alignment
- ✅ Impulse Propagation
- ✅ DC Input Test
- ✅ Stress Test

**Quick Run:**
```powershell
.\run_vivado_tests.ps1 top
```

---

### 3. **all_modules_tb.sv** - Comprehensive Suite
Tests all 8 ATCNet modules independently

**Modules Tested (8):**
1. ✅ temporal_conv
2. ✅ dual_branch_conv
3. ✅ channel_scale
4. ✅ window_gen
5. ✅ window_reader
6. ✅ spatial_conv_serial_stream
7. ✅ temporal_fusion
8. ✅ temporal_multihead_attention

**Quick Run:**
```powershell
.\run_vivado_tests.ps1 all
```

---

## 🚀 Running Tests

### PowerShell Script (Easiest)
```powershell
# Run from sim directory
cd c:\College\Graduation\FPGA\fpga-atcnet\sim

# Run individual test
.\run_vivado_tests.ps1 temporal  # Unit test (5-10 sec)
.\run_vivado_tests.ps1 top       # Integration test (10-30 sec)
.\run_vivado_tests.ps1 all       # Full suite (30-60 sec)
```

### Vivado Command Line
```powershell
cd c:\College\Graduation\FPGA\fpga-atcnet

# Temporal conv test
xvlog --sv rtl/conv/temporal_conv.sv sim/temporal_conv_tb.sv
xelab temporal_conv_tb -debug typical
xsim temporal_conv_tb -runall

# Top integration test
xvlog --sv rtl/conv/temporal_conv.sv rtl/conv/dual_branch_conv.sv rtl/conv/channel_scale.sv rtl/window/window_gen.sv rtl/window/window_reader.sv rtl/top.sv sim/top_tb.sv
xelab top_tb -debug typical
xsim top_tb -runall
```

### Vivado GUI
```tcl
# Open Vivado and use TCL console
cd C:/College/Graduation/FPGA/fpga-atcnet
read_verilog -sv rtl/conv/temporal_conv.sv sim/temporal_conv_tb.sv
synth_design -top temporal_conv_tb -part xc7a35ticsg324-1L
launch_simulation
add_wave /*
run 500us
```

---

## 📊 Expected Output

### Successful Test Run
```
========================================
ATCNet Temporal Convolution Testbench
========================================

TEST 1: Impulse Response
  ✓ PASS - Impulse response correct

TEST 2: DC Response
  ✓ PASS - DC response correct

...

  ALL TESTS PASSED!
  temporal_conv.sv is VERIFIED
```

### Failed Test
```
TEST 3: Ramp Response
  ✗ FAIL - Expected 1.234, got 1.567
```

---

## 🔧 Testbench Features

### Fixed-Point Arithmetic
- **Format:** Q8.8 (8 integer bits, 8 fractional bits)
- **Helper Functions:** `float_to_fixed()` and `fixed_to_float()`
- **Range:** -128.0 to +127.996

### Timing
- **Clock Period:** 10ns (100MHz)
- **Reset:** Active high, 5 cycles
- **Timeout:** Automatic simulation timeout to prevent hangs

### Assertions
- Automatic pass/fail detection
- Numerical tolerance checking
- Latency verification

---

## 📁 File Organization

```
sim/
├── temporal_conv_tb.sv          # Unit test (temporal_conv)
├── top_tb.sv                    # Integration test (full pipeline)
├── all_modules_tb.sv            # Comprehensive test (all 8 modules)
├── run_vivado_tests.ps1         # Automated test runner
├── TESTBENCH_README.md          # This file
└── VIVADO_USAGE.md              # Detailed Vivado usage guide
```

---

## 🐛 Troubleshooting

### "Cannot find module 'temporal_conv'"
**Solution:** Compile RTL files before testbench
```powershell
xvlog --sv rtl/conv/temporal_conv.sv   # RTL first
xvlog --sv sim/temporal_conv_tb.sv     # Then testbench
```

### "Simulation doesn't start"
**Solution:** Check for syntax errors
```powershell
xvlog --sv sim/temporal_conv_tb.sv  # Look for errors in output
```

### "Test fails unexpectedly"
**Solution:** 
1. View waveforms in Vivado GUI
2. Check module connections
3. Verify clock/reset timing
4. Check fixed-point conversions

### "Script execution disabled"
**Solution:**
```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

---

## 📚 Additional Resources

- **[VIVADO_USAGE.md](VIVADO_USAGE.md)** - Detailed Vivado guide with multiple execution methods
- **Vivado User Guide (UG900)** - Official Xilinx simulation documentation
- **SystemVerilog LRM** - Language reference for advanced features

---

## ✅ Test Status

| Testbench | Status | Time | Coverage |
|-----------|--------|------|----------|
| temporal_conv_tb.sv | ✅ Ready | ~10s | 1 module, 6 tests |
| top_tb.sv | ✅ Ready | ~30s | 5 modules, 6 tests |
| all_modules_tb.sv | ✅ Ready | ~60s | 8 modules, 8 tests |

**Total:** 3 testbenches, 20+ test cases, 8 modules tested

---

## 🎯 Next Steps

1. ✅ Run `temporal_conv_tb` - Verify basic functionality
2. ✅ Check console output - All tests should PASS
3. ✅ Run `top_tb` - Verify pipeline integration
4. ✅ Run `all_modules_tb` - Comprehensive validation
5. ✅ View waveforms - Analyze timing if needed
6. ✅ Proceed to synthesis - After all tests pass

---

**Last Updated:** January 6, 2026  
**Compatible With:** Vivado 2019.1+  
**SystemVerilog:** IEEE 1800-2012
