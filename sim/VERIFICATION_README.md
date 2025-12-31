# Temporal Convolution Verification Guide

---

## 🎯 Overview

Complete SystemVerilog testbench for verifying the `temporal_conv.sv` module with:
- ✅ **7 automated test cases** (impulse, DC, ramp, latency, streaming, dilation, edge cases)
- ✅ **Cycle-accurate latency measurement** - Verifies pipeline timing
- ✅ **Numerical correctness** - Fixed-point Q8.8 format validation
- ✅ **Protocol compliance** - Valid signal behavior
- ✅ **Automatic pass/fail** - No manual checking required

---

## 📦 Files Created

```
fpga-atcnet/
├── sim/
│   ├── temporal_conv_tb.sv         # Main testbench (7 tests)
│   ├── run_temporal_conv_tb.do     # ModelSim automation
│   └── VERIFICATION_README.md      # This file
├── scripts/
│   ├── run_verification.bat        # Windows runner
│   └── run_verification.sh         # Linux/Mac runner
└── rtl/conv/
    └── temporal_conv.sv            # Module to verify (Person 1)
```

---

## 🚀 Quick Start

### Option 1: Automated (Recommended)
```bash
cd scripts
./run_verification.sh    # Linux/Mac
# or
run_verification.bat     # Windows
```

### Option 2: Manual Simulation

**ModelSim:**
```bash
cd sim
vsim -do run_temporal_conv_tb.do
```

**Icarus Verilog:**
```bash
cd sim
iverilog -g2012 -o tb.vvp temporal_conv_tb.sv ../rtl/conv/temporal_conv.sv
vvp tb.vvp
```

**Verilator:**
```bash
cd sim
verilator --cc --exe --build temporal_conv_tb.sv ../rtl/conv/temporal_conv.sv
./obj_dir/Vtemporal_conv_tb
```

### Expected Output
```
╔════════════════════════════════════════════╗
║     TEST SUMMARY                           ║
╚════════════════════════════════════════════╝
  Total tests:   7
  Passed:        7    ← All should pass!
  Passed:        0    ← Should be 0!
  
  ████████╗███████╗███████╗████████╗    ██████╗  █████╗ ███████╗███████╗
```

---

## 🧪 Test Cases

The testbench includes 7 comprehensive tests:

### 1. Impulse Response
- **Tests**: Basic convolution operation
- **Input**: Single impulse (1.0), rest zeros
- **Checks**: Output matches expected convolution

### 2. DC Response
- **Tests**: Constant signal handling
- **Input**: Constant value (1.0)
- **Checks**: Output stability and correctness

### 3. Ramp Response
- **Tests**: Linearity
- **Input**: Linear ramp pattern
- **Checks**: Output follows expected linear relationship

### 4. Latency Measurement ⏱️
- **Tests**: Cycle-accurate timing
- **Measures**: Cycles from first input to first valid output
- **Expected**: KERNEL_SIZE cycles (for causal padding)
- **Critical**: This validates your pipeline depth!

### 5. Streaming with Valid Gaps
- **Tests**: Protocol compliance
- **Input**: Data with random valid gaps
- **Checks**: Correct operation regardless of gaps

### 6. Dilation Test
- **Tests**: Dilated convolution (if DILATION > 1)
- **Checks**: Proper dilation behavior

### 7. Edge Cases
- **Tests**: Robustness
- **Inputs**: All zeros, max values, negative values
- **Checks**: No overflows, correct handling

---

## 🔧 Configuration

### Module Parameters (in testbench)
```systemverilog
parameter int DATA_WIDTH = 16;      // Total bits
parameter int FRAC_BITS = 8;        // Q8.8 fixed-point
parameter int IN_CHANNELS = 32;     // Input channels
parameter int OUT_CHANNELS = 32;    // Output channels
parameter int KERNEL_SIZE = 4;      // Temporal kernel size
parameter int DILATION = 1;         // Dilation rate
```

### Fixed-Point Format: Q8.8
- **Range**: -128.0 to +127.996
- **Resolution**: 1/256 ≈ 0.0039
- **Example**: 0x0180 = 1.5

---

## 🐛 Debugging Failed Tests

### Step 1: Check Console Output
Look for specific test failures:
```
[FAIL] Test 4: Latency mismatch!
  Measured: 5 cycles
  Expected: 4 cycles
```

### Step 2: View Waveforms
```bash
gtkwave sim/temporal_conv_tb.vcd
```

**Key signals:**
- `clk`, `rst_n` - Basic operation
- `data_in_valid`, `data_out_valid` - Protocol
- `data_in[0]`, `data_out[0]` - Data values
- Internal shift registers (if visible)
- MAC accumulators (if visible)

### Step 3: Common Issues & Solutions

#### Issue: Latency Mismatch
```
Measured latency: 5 cycles
Expected latency: 4 cycles
```
**Causes:**
- Extra pipeline stage
- Incorrect KERNEL_SIZE parameter
- Missing fast-forward path

**Fix:** Check pipeline depth in `temporal_conv.sv`

#### Issue: All Outputs Zero
```
[FAIL] Expected impulse in output
  Got: 0.0000
```
**Causes:**
- Kernel weights not loaded
- MAC not working
- Output register not updating

**Fix:** 
- Verify `kernel_weights` port connection
- Check MAC logic: `acc = acc + (data * weight);`

#### Issue: Numerical Errors
```
[FAIL] Channel 2: Expected 0x0100, Got 0x0105
```
**Causes:**
- Insufficient accumulator width
- Wrong rounding mode
- Overflow

**Fix:**
```systemverilog
// Increase accumulator width
parameter ACC_WIDTH = DATA_WIDTH + $clog2(KERNEL_SIZE * IN_CHANNELS);

// Add proper rounding
output_reg <= (acc + (1 << (FRAC_BITS-1))) >>> FRAC_BITS;
```

#### Issue: No Valid Output
```
[FATAL] Timeout waiting for output
```
**Causes:**
- Valid signal stuck at 0
- Reset not deasserted
- Pipeline not advancing

**Fix:**
- Check `rst_n` goes high
- Verify valid propagation logic
- Check shift register enable

---

## 📊 Performance Metrics

### Latency
- **Definition**: Cycles from first input to first valid output
- **Target**: KERNEL_SIZE cycles
- **Measured in**: Test 4

### Throughput
- **Definition**: Valid outputs per cycle
- **Target**: 1 output/cycle (after initial latency)
- **Measured in**: Test 2

### Accuracy
- **Definition**: Fixed-point error
- **Target**: ≤ 2 LSB for Q8.8
- **Tolerance**: ±0.0078

---

## 🔍 Testbench Architecture

### Helper Functions Available
```systemverilog
// Convert float to fixed-point
function logic [15:0] float_to_fixed(real value);
    return int'($floor(value * 256.0 + 0.5));
endfunction

// Convert fixed-point to float
function real fixed_to_float(logic [15:0] value);
    int signed temp = signed'(value);
    return real'(temp) / 256.0;
endfunction

// Compare with tolerance
function bit compare_fixed(logic [15:0] actual, expected, int tolerance=2);
    int diff = abs(signed'(actual) - signed'(expected));
    return (diff <= tolerance);
endfunction
```

### Running Single Test
To debug one test at a time, comment out others in testbench:
```systemverilog
// test_impulse_response();
// test_dc_response();
test_latency();  // Debug this one only
// test_ramp_response();
```

---

## 🤝 Integration with Team

### For Person 1 (temporal_conv.sv owner)
1. Implement `rtl/conv/temporal_conv.sv`
2. Run: `./scripts/run_verification.sh`
3. If tests fail, debug using this guide
4. Iterate until all 7 tests pass
5. Ready for integration!

### Interface Requirements
```systemverilog
module temporal_conv #(
    parameter int DATA_WIDTH = 16,
    parameter int IN_CHANNELS = 32,
    parameter int OUT_CHANNELS = 32,
    parameter int KERNEL_SIZE = 4
) (
    input  logic clk,
    input  logic rst_n,
    input  logic [IN_CHANNELS-1:0][DATA_WIDTH-1:0] data_in,
    input  logic data_in_valid,
    output logic [OUT_CHANNELS-1:0][DATA_WIDTH-1:0] data_out,
    output logic data_out_valid,
    input  logic [KERNEL_SIZE-1:0][IN_CHANNELS-1:0][OUT_CHANNELS-1:0][DATA_WIDTH-1:0] kernel_weights,
    input  logic [OUT_CHANNELS-1:0][DATA_WIDTH-1:0] bias
);
```

### For Person 2 (window_gen.sv owner)
After temporal_conv passes tests:
```systemverilog
// Your window_gen output feeds into temporal_conv
temporal_conv conv_inst (
    .clk(clk),
    .rst_n(rst_n),
    .data_in(window_output),      // From window_gen
    .data_in_valid(window_valid),
    .data_out(conv_output),
    .data_out_valid(conv_valid)
);
```

---

## ✅ Verification Checklist

Before declaring verification complete:

- [ ] All 7 unit tests pass
- [ ] Latency = KERNEL_SIZE cycles
- [ ] Numerical accuracy within tolerance
- [ ] Waveforms reviewed and look correct
- [ ] Edge cases handled properly
- [ ] No synthesis warnings
- [ ] Code reviewed by team
- [ ] Ready for integration

---

## 📝 Quick Reference

### Run Simulation
```bash
cd scripts && ./run_verification.sh
```

### View Waveforms
```bash
gtkwave sim/temporal_conv_tb.vcd
```

### Check Simulation Log
```bash
cat sim/simulation.log
```

### Common Test Results
- ✅ **All tests pass** → Ready for integration
- ⚠️ **Latency mismatch** → Check pipeline stages
- ⚠️ **Numerical errors** → Check accumulator width
- ❌ **No valid output** → Check valid propagation

---

## 🎓 Understanding the TCNet Model

Your testbench validates the TCFN (Temporal Convolutional Fusion Network) block from the Python model:
- **First layer**: Conv1D with dilation=1
- **Subsequent layers**: Conv1D with dilation=2^i (i=1,2,...)
- **Residual connections**: Between layers
- **Causal padding**: Future samples not visible

The RTL implementation must match this behavior!

---

## 💡 Tips

1. **Start simple**: Run Test 1 (impulse) first
2. **Use waveforms**: Don't debug blind
3. **Check console**: Detailed error messages provided
4. **One test at a time**: Comment out others to focus
5. **Verify parameters**: Make sure testbench matches your RTL
6. **Ask team**: Don't spend hours stuck!

---

## 📞 Support

- **Testbench owner**: Person 3
- **Module owner**: Person 1 (temporal_conv.sv)
- **Integration**: Person 2 (window_gen.sv)

---

**Status**: ✅ Testbench ready and waiting for RTL implementation  
**Last Updated**: December 31, 2025  
**Version**: 1.0
