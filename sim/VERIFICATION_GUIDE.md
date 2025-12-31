# Temporal Convolution Verification Guide
**Owner: Person 3**

## Overview
This verification infrastructure validates the `temporal_conv.sv` module against the Python TCNet model, ensuring:
- ✅ **Cycle-accurate latency** - Output timing matches specification
- ✅ **Numerical correctness** - Fixed-point results match golden reference within tolerance
- ✅ **Protocol compliance** - Valid signals behave correctly
- ✅ **Edge case handling** - Robust operation under all conditions

---

## Architecture

### Test Infrastructure Components

```
python/
├── generate_test_vectors.py    # Generates golden reference from TCNet
├── verify_results.py            # Compares RTL vs Python outputs  
└── quick_test.py                # Minimal sanity check

sim/
├── temporal_conv_tb.sv          # Main SystemVerilog testbench
├── run_temporal_conv_tb.do      # ModelSim automation script
├── test_params.svh              # Auto-generated parameters
└── *.json                       # Test vector files

scripts/
├── run_verification.bat         # Windows automation
└── run_verification.sh          # Linux/Mac automation
```

### Data Flow
```
┌─────────────────┐
│  TCNet Model    │ (models.py - TCFN block)
│   (Python)      │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Test Generator  │ (generate_test_vectors.py)
│                 │ - Extract weights
└────────┬────────┘ - Compute golden outputs
         │          - Convert to fixed-point
         ▼
┌─────────────────┐
│  Test Vectors   │ (*.json files)
│  + Config       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ RTL Testbench   │ (temporal_conv_tb.sv)
│                 │ - Load test vectors
│                 │ - Stimulate DUT
│                 │ - Capture outputs
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ RTL Outputs     │ (rtl_output.txt)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Verification    │ (verify_results.py)
│ Checker         │ - Compare outputs
│                 │ - Report errors
└─────────────────┘
```

---

## Quick Start

### 1️⃣ Generate Test Vectors
```bash
cd python
python generate_test_vectors.py
```
**Output**: Test vectors in `../sim/*.json`

### 2️⃣ Run Quick Sanity Check
```bash
python quick_test.py
```
**Output**: Minimal test case for basic verification

### 3️⃣ Run RTL Simulation

**Option A: Automated (Recommended)**
```bash
# Windows
cd scripts
run_verification.bat

# Linux/Mac
cd scripts
chmod +x run_verification.sh
./run_verification.sh
```

**Option B: Manual**
```bash
cd sim

# ModelSim
vsim -do run_temporal_conv_tb.do

# Icarus Verilog
iverilog -g2012 -o temporal_conv_tb.vvp temporal_conv_tb.sv ../rtl/conv/temporal_conv.sv
vvp temporal_conv_tb.vvp
```

### 4️⃣ Verify Results
```bash
cd python
python verify_results.py ../sim/rtl_output.txt ../sim/simple_case.json
```

---

## Test Cases

### 1. Impulse Response Test
**Purpose**: Verify basic convolution operation  
**Method**: Send impulse (1.0 in one channel), observe output  
**Pass Criteria**: Output matches impulse convolved with kernel

### 2. DC Response Test  
**Purpose**: Verify constant signal handling  
**Method**: Send constant value, check output stability  
**Pass Criteria**: Output equals input averaged by kernel

### 3. Ramp Response Test
**Purpose**: Verify linearity  
**Method**: Send linear ramp, check output linearity  
**Pass Criteria**: Output follows expected linear relationship

### 4. Latency Measurement
**Purpose**: Verify cycle-accurate timing  
**Method**: Measure cycles from first input to first valid output  
**Expected Latency**: `KERNEL_SIZE` cycles (for causal padding)  
**Pass Criteria**: Measured latency = Expected latency

### 5. Streaming with Gaps
**Purpose**: Verify valid signal handling  
**Method**: Send data with random valid gaps  
**Pass Criteria**: Outputs appear correctly regardless of gaps

### 6. Dilation Test (if DILATION > 1)
**Purpose**: Verify dilated convolution  
**Method**: Test with dilated kernels  
**Pass Criteria**: Outputs match dilated convolution math

### 7. Edge Cases
**Purpose**: Robust operation verification  
**Tests**:
- All zeros input → zero output
- Maximum values → no overflow
- Negative values → correct signed arithmetic

---

## Understanding Fixed-Point Format

### Q8.8 Format (Default)
```
15 14 13 12 11 10  9  8  7  6  5  4  3  2  1  0
 S  I  I  I  I  I  I  I  F  F  F  F  F  F  F  F
 │  └──────┬──────────┘  └──────────┬──────────┘
Sign    Integer (7 bits)      Fraction (8 bits)
```

- **Range**: -128.0 to +127.99609375
- **Resolution**: 1/256 ≈ 0.00390625
- **Example**: 0x0180 = 384 / 256 = 1.5

### Tolerance
- **Default**: ±2 LSB = ±0.0078125
- **Reason**: Rounding errors in MAC accumulation
- **Configurable**: Pass as argument to verify_results.py

---

## Interpreting Results

### Successful Test Output
```
╔════════════════════════════════════════════════════════════╗
║     TEST SUMMARY                                           ║
╚════════════════════════════════════════════════════════════╝

  Total tests:   7
  Passed:        7
  Failed:        0
  Total cycles:  542

  ████████╗███████╗███████╗████████╗    ██████╗  █████╗ ███████╗███████╗███████╗██████╗ 
  ...
```

### Failed Test Output
```
[ERROR] Channel 2 mismatch in test_dc_response
  Expected: 0x0100 (1.0000)
  Got:      0x0102 (1.0078)
  Diff:     0x0002
```

### Verification Report
```
Samples compared: 32
Sample mismatches: 0
Total value errors: 0
Pass rate: 100.00%
```

---

## Debugging Failed Tests

### Step 1: Check Simulation Log
```bash
cat sim/temporal_conv_tb.log
```
Look for:
- Compilation errors
- Runtime assertions
- $display messages

### Step 2: View Waveforms
```bash
gtkwave sim/temporal_conv_tb.vcd
```
**Key signals to check**:
- `clk`, `rst_n` - Basic operation
- `data_in_valid`, `data_out_valid` - Protocol
- `data_in`, `data_out` - Data values
- DUT internal shift registers
- DUT MAC accumulators

### Step 3: Read Verification Report
```bash
cat verification_report.txt
```
Shows:
- Total errors and warnings
- Detailed error breakdown
- Channel-by-channel mismatches

### Step 4: Compare Individual Samples
Enable verbose mode in testbench:
```systemverilog
// In temporal_conv_tb.sv
if (data_out_valid) begin
    $display("[VERBOSE] t=%0d, out[0]=%h (%f)", 
             cycle_count, data_out[0], fixed_to_float(data_out[0]));
end
```

### Step 5: Isolate the Problem
Run single test:
```systemverilog
// Comment out other tests
test_impulse_response();  // Only run this
// test_dc_response();
// test_ramp_response();
```

---

## Common Issues & Solutions

### Issue: Latency Mismatch
**Symptoms**: 
```
Measured latency: 5 cycles
Expected latency: 4 cycles
[FAIL] Latency mismatch!
```
**Causes**:
- Extra pipeline stage in temporal_conv.sv
- Missing fast-forward path
- Incorrect KERNEL_SIZE parameter

**Solution**:
1. Check pipeline depth in RTL
2. Verify shift register implementation
3. Check if causal padding adds extra cycle

---

### Issue: Numerical Errors > Tolerance
**Symptoms**:
```
Channel 2 mismatch
  Diff: 5 LSB (exceeds tolerance of 2 LSB)
```
**Causes**:
- Insufficient MAC accumulator width
- Incorrect rounding mode
- Overflow in intermediate calculations

**Solution**:
1. Increase accumulator width: `parameter ACC_WIDTH = DATA_WIDTH + $clog2(KERNEL_SIZE * IN_CHANNELS);`
2. Add rounding: `output_reg <= (acc + (1 << (FRAC_BITS-1))) >>> FRAC_BITS;`
3. Check for overflows: `assert(acc < MAX_VAL);`

---

### Issue: Valid Signal Never Asserts
**Symptoms**:
```
[FATAL] Timeout waiting for output
```
**Causes**:
- Valid signal stuck at 0
- Pipeline not advancing
- Reset not deasserted

**Solution**:
1. Check reset logic: `rst_n` must go high
2. Verify valid propagation through pipeline
3. Check shift register enable signal

---

### Issue: All Outputs are Zero
**Symptoms**:
```
[FAIL] Expected impulse in output channel 0
  Got: 0.0000
```
**Causes**:
- Kernel weights not loaded
- Multiply-accumulate not working
- Output register not updating

**Solution**:
1. Verify `kernel_weights` port connection
2. Check MAC logic: `acc = acc + (data * weight);`
3. Ensure output register is clocked

---

## Performance Metrics

### Latency
**Definition**: Cycles from first input to first valid output  
**Target**: `KERNEL_SIZE` cycles  
**Measurement**: Automated in `test_latency()`

### Throughput
**Definition**: Valid outputs per cycle  
**Target**: 1 output/cycle (after initial latency)  
**Measurement**: Count valid outputs over time

### Accuracy
**Definition**: Fixed-point error vs golden reference  
**Target**: ≤ 2 LSB for Q8.8  
**Measurement**: Automated in `verify_results.py`

### Resource Utilization
**Measured after synthesis**:
- LUTs
- Flip-flops  
- DSP blocks (for MAC)
- BRAM (for weights)

---

## Integration Testing

After passing unit tests, integrate with other modules:

### With window_gen.sv
```systemverilog
window_gen → temporal_conv → ...
```
Test: Sliding window outputs feed correctly into convolution

### With Attention Block  
```systemverilog
temporal_conv → attention → temporal_conv
```
Test: Multi-stage TCN block

### Full TCNet Pipeline
```systemverilog
Input → Conv → Window → Attention → TCN → Fusion → Output
```
Test: End-to-end EEG classification

---

## Advanced Verification

### Constrained Random Testing
```python
# In generate_test_vectors.py
input_seq = np.random.randn(seq_length, in_channels) * 0.1
kernel = np.random.randn(kernel_size, in_channels, out_channels) * 0.1
```

### Coverage Metrics
Track:
- Valid gap patterns
- Input value ranges
- Kernel weight distributions
- Edge case combinations

### Formal Verification (Future)
Use formal tools to prove:
- No overflows
- Valid always arrives within N cycles
- Causality preserved

---

## Checklist

Before marking verification complete:

- [ ] All 7 unit tests pass
- [ ] Latency matches expected value
- [ ] No numerical errors > tolerance  
- [ ] Waveforms reviewed and look correct
- [ ] Verified with multiple random seeds
- [ ] Edge cases handled properly
- [ ] Documentation updated
- [ ] Code reviewed by team
- [ ] Synthesis runs without errors
- [ ] Timing constraints met

---

## Next Steps

1. **Complete person 1's temporal_conv.sv implementation**
2. **Run verification**: `./scripts/run_verification.sh`
3. **Debug any failures** using guide above
4. **Iterate until all tests pass**
5. **Integrate with window_gen.sv** (person 2's module)
6. **Verify integrated system**
7. **Synthesize for FPGA**
8. **Timing analysis**
9. **Hardware bring-up**

---

## Contact & Support

**Verification Lead**: Person 3  
**Module Owner**: Person 1 (temporal_conv.sv)  
**Integration**: Person 2 (window_gen.sv)

**Questions?** Check:
1. This guide
2. README_VERIFICATION.md
3. Code comments in testbench
4. Ask your teammates!

---

## References

- TCNet Paper: [EEG-TCNet](https://arxiv.org/abs/2006.00622)
- ATCNet Paper: [ATCNet](https://doi.org/10.1109/TII.2022.3197419)
- Python model: `models.py` - TCFN block
- SystemVerilog testbench: `temporal_conv_tb.sv`

---

**Last Updated**: December 31, 2025  
**Version**: 1.0
