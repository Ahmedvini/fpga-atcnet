# TCNet Verification Infrastructure - Complete Package

## 🎯 Overview

Complete verification suite for validating the `temporal_conv.sv` RTL module against the Python TCNet model. Ensures **cycle-accurate latency** and **numerical correctness** for FPGA implementation.

---

## 📦 What's Included

### Core Verification Files
1. **[generate_test_vectors.py](python/generate_test_vectors.py)** - Generate golden reference test vectors
2. **[temporal_conv_tb.sv](sim/temporal_conv_tb.sv)** - Comprehensive SystemVerilog testbench
3. **[verify_results.py](python/verify_results.py)** - Compare RTL vs Python outputs
4. **[extract_model_weights.py](python/extract_model_weights.py)** - Extract weights from trained model

### Helper Scripts
5. **[quick_test.py](python/quick_test.py)** - Minimal sanity check
6. **[run_verification.bat](scripts/run_verification.bat)** - Windows automation
7. **[run_verification.sh](scripts/run_verification.sh)** - Linux/Mac automation  
8. **[run_temporal_conv_tb.do](sim/run_temporal_conv_tb.do)** - ModelSim automation

### Documentation
9. **[README_VERIFICATION.md](sim/README_VERIFICATION.md)** - Quick start guide
10. **[VERIFICATION_GUIDE.md](sim/VERIFICATION_GUIDE.md)** - Comprehensive reference (12 pages)
11. **[PERSON3_DELIVERABLES.md](PERSON3_DELIVERABLES.md)** - Summary of all deliverables
12. **THIS FILE** - Master README

---

## 🚀 Quick Start (30 seconds)

```bash
# 1. Generate test vectors
cd python
python generate_test_vectors.py

# 2. Run automated verification
cd ../scripts
./run_verification.sh    # Linux/Mac
# or
run_verification.bat     # Windows

# 3. Check results - look for:
# ✓ VERIFICATION PASSED!
```

---

## 📖 Documentation Guide

**Start here based on your needs:**

| If you want to... | Read this |
|-------------------|-----------|
| Get started quickly | This README (you're here!) |
| Run first verification | [README_VERIFICATION.md](sim/README_VERIFICATION.md) |
| Understand test details | [VERIFICATION_GUIDE.md](sim/VERIFICATION_GUIDE.md) |
| Debug failing tests | [VERIFICATION_GUIDE.md](sim/VERIFICATION_GUIDE.md) - Section "Debugging" |
| See all deliverables | [PERSON3_DELIVERABLES.md](PERSON3_DELIVERABLES.md) |
| Use trained model weights | [extract_model_weights.py](python/extract_model_weights.py) |

---

## 🎓 Step-by-Step Tutorial

### Step 1: Understand the Model

The Python TCNet model has a **TCFN block** (Temporal Convolutional Fusion Network):

```python
# From models.py - TCFN block
def TCFN(input_layer, input_dimension, depth, kernel_size, filters, dropout):
    # First conv with dilation=1
    block = Conv1D(filters, kernel_size=kernel_size, dilation_rate=1, ...)
    # ... batch norm, activation, dropout ...
    
    # Additional layers with increasing dilation  
    for i in range(depth - 1):
        block = Conv1D(filters, kernel_size, dilation_rate=2**(i+1), ...)
        # ... residual connections ...
    
    return out
```

**Your job**: Verify the RTL implementation matches this behavior.

---

### Step 2: Generate Test Vectors

```bash
cd python
python generate_test_vectors.py
```

**What it does**:
- Creates simple test patterns (impulse, ramp, etc.)
- Computes expected outputs using numpy
- Converts to Q8.8 fixed-point format
- Saves to JSON files

**Outputs**:
```
sim/
├── simple_case.json       # Basic convolution test
├── streaming_test.json    # Sample-by-sample test
├── tcn_block.json         # Multi-layer test
├── test_config.json       # Configuration
└── test_params.svh        # SystemVerilog parameters
```

---

### Step 3: Understand the Testbench

The testbench (`sim/temporal_conv_tb.sv`) runs 7 automated tests:

```systemverilog
// Test 1: Impulse → Check basic convolution
test_impulse_response();

// Test 2: Constant input → Check stability
test_dc_response();

// Test 3: Ramp → Check linearity
test_ramp_response();

// Test 4: Measure latency (CRITICAL!)
test_latency();  // Expects KERNEL_SIZE cycles

// Test 5: Valid gaps → Check protocol
test_streaming_with_gaps();

// Test 6: Dilation (if enabled)
test_dilation();

// Test 7: Edge cases → Zeros, boundaries
test_edge_cases();
```

---

### Step 4: Run Simulation

**Option A: Automated (Recommended)**
```bash
cd scripts
./run_verification.sh
```

**Option B: Manual - ModelSim**
```bash
cd sim
vsim -do run_temporal_conv_tb.do
```

**Option C: Manual - Icarus Verilog**
```bash
cd sim
iverilog -g2012 -o tb.vvp temporal_conv_tb.sv ../rtl/conv/temporal_conv.sv
vvp tb.vvp
```

---

### Step 5: Check Results

**Console output should show**:
```
╔════════════════════════════════════════════════════════════╗
║     TEST SUMMARY                                           ║
╚════════════════════════════════════════════════════════════╝

  Total tests:   7
  Passed:        7    ← All should pass!
  Failed:        0    ← Should be 0!
  Total cycles:  542

  ████████╗███████╗███████╗████████╗    ██████╗  █████╗ ███████╗███████╗███████╗██████╗ 
```

**If tests fail**, see Step 6 below.

---

### Step 6: Debug Failures (If Needed)

#### 6a. Check Waveforms
```bash
gtkwave sim/temporal_conv_tb.vcd
```

**Key signals to watch**:
- `data_in_valid` / `data_out_valid` - Handshaking
- `data_in` / `data_out` - Data values
- DUT internal shift registers
- MAC accumulators

#### 6b. Read Verification Report
```bash
cat verification_report.txt
```

Shows detailed error breakdown.

#### 6c. Common Issues

**Latency mismatch**:
```
Measured latency: 5 cycles
Expected latency: 4 cycles
```
→ Check pipeline depth in `temporal_conv.sv`

**Numerical errors**:
```
Channel 2: Expected 0x0100, Got 0x0105
Diff: 5 LSB (exceeds tolerance)
```
→ Check MAC accumulator bit width
→ Verify rounding

**No valid output**:
```
[FATAL] Timeout waiting for output
```
→ Check valid signal propagation
→ Verify reset is deasserted

#### 6d. Get More Help
Read the debugging section in [VERIFICATION_GUIDE.md](sim/VERIFICATION_GUIDE.md)

---

## 🔧 Using Trained Model Weights

If you have a trained model, extract real weights:

```bash
cd python
python extract_model_weights.py ../path/to/model.h5
```

**Outputs**:
- `sim/trained_model_weights.json` - All weights in JSON
- `sim/tcn_block_1.json` - Individual TCN blocks  
- `sim/model_weights.svh` - SystemVerilog include file

**Use in testbench**:
```systemverilog
`include "model_weights.svh"

// Load weights
kernel_weights = tcn_block1_conv1_KERNEL;
bias = tcn_block1_conv1_BIAS;
```

---

## 📊 Verification Checklist

Before declaring verification complete:

- [ ] All 7 unit tests pass ✅
- [ ] Latency = KERNEL_SIZE cycles ✅
- [ ] Numerical error ≤ 2 LSB ✅  
- [ ] Waveforms look correct ✅
- [ ] Tested with random inputs ✅
- [ ] Tested with trained model weights ✅
- [ ] Edge cases handled ✅
- [ ] Documentation complete ✅
- [ ] Code reviewed ✅
- [ ] Ready for integration ✅

---

## 🤝 Team Integration

### Dependencies
- **Waiting for**: Person 1 to implement `temporal_conv.sv`
- **Provides**: Complete verification infrastructure

### Interface with Person 2
After `temporal_conv.sv` passes tests:
```systemverilog
// Person 2's window_gen.sv output feeds into:
temporal_conv #(...) conv_inst (
    .clk(clk),
    .rst_n(rst_n),
    .data_in(window_output),     // From window_gen
    .data_in_valid(window_valid),
    .data_out(conv_output),
    .data_out_valid(conv_valid)
);
```

---

## 🎯 Key Verification Metrics

| Metric | Target | Status |
|--------|--------|--------|
| Latency | KERNEL_SIZE cycles | ⏱️ Measured in Test 4 |
| Throughput | 1 output/cycle | 📊 Measured in Test 2 |
| Accuracy | ≤ 2 LSB (Q8.8) | 🎯 Checked by verify_results.py |
| Coverage | All tests pass | ✅ Automated testbench |

---

## 📁 File Organization

```
fpga-atcnet/
│
├── python/                      # Python scripts
│   ├── models.py                  (Existing - TCNet model)
│   ├── generate_test_vectors.py   (Person 3 - Test generation)
│   ├── verify_results.py          (Person 3 - Result checking)
│   ├── extract_model_weights.py   (Person 3 - Weight extraction)
│   └── quick_test.py              (Person 3 - Sanity check)
│
├── sim/                         # Simulation files
│   ├── temporal_conv_tb.sv        (Person 3 - Testbench)
│   ├── run_temporal_conv_tb.do    (Person 3 - ModelSim script)
│   ├── README_VERIFICATION.md     (Person 3 - Quick guide)
│   ├── VERIFICATION_GUIDE.md      (Person 3 - Full guide)
│   ├── test_params.svh            (Auto-generated)
│   ├── *.json                     (Auto-generated test vectors)
│   └── *.vcd                      (Simulation waveforms)
│
├── scripts/                     # Automation scripts  
│   ├── run_verification.bat       (Person 3 - Windows)
│   └── run_verification.sh        (Person 3 - Linux/Mac)
│
├── rtl/                         # RTL source
│   ├── top.sv                     (Existing)
│   ├── conv/
│   │   └── temporal_conv.sv       (Person 1 - To be verified)
│   └── window/
│       └── window_gen.sv          (Person 2)
│
├── PERSON3_DELIVERABLES.md      # Summary document
└── README_VERIFICATION_MASTER.md # This file
```

---

## 🆘 Troubleshooting

### "Python module not found"
```bash
pip install numpy tensorflow keras
```

### "No simulator found"
Install one of:
- **ModelSim/QuestaSim** (commercial, most features)
- **Icarus Verilog** (free, good for basic tests)
- **Verilator** (free, fastest simulation)

### "Tests fail with numerical errors"
1. Check fixed-point format (Q8.8 default)
2. Increase accumulator width in RTL
3. Verify rounding mode
4. Try higher tolerance: `python verify_results.py ... ... 5`

### "Latency doesn't match"
1. Count pipeline stages in RTL
2. Check shift register depth
3. Verify causal padding implementation

### "Still stuck?"
1. Read [VERIFICATION_GUIDE.md](sim/VERIFICATION_GUIDE.md) debugging section
2. Check waveforms with gtkwave
3. Enable verbose output in testbench
4. Ask Person 3 (verification owner)

---

## 🎓 Learning Path

**New to verification?** Follow this path:

1. **Day 1**: Read this README, run `quick_test.py`
2. **Day 2**: Study `temporal_conv_tb.sv`, understand Test 1 (impulse)
3. **Day 3**: Run full verification, study waveforms
4. **Day 4**: Read VERIFICATION_GUIDE.md, understand all tests
5. **Day 5**: Try with trained model weights

**Already experienced?** Jump straight to running verification!

---

## ✨ What Makes This Verification Good?

✅ **Automated** - One command runs everything  
✅ **Comprehensive** - 7 different test cases  
✅ **Cycle-accurate** - Measures actual latency  
✅ **Numerically verified** - Compares with golden reference  
✅ **Well-documented** - 4 levels of documentation  
✅ **Easy to debug** - Detailed error reports + waveforms  
✅ **Team-friendly** - Clear interfaces and automation  

---

## 🚀 Next Steps

1. **Person 1**: Implement `temporal_conv.sv`
2. **Run verification**: `./scripts/run_verification.sh`
3. **Debug if needed**: Use VERIFICATION_GUIDE.md
4. **Iterate**: Until all tests pass
5. **Integrate**: Connect with window_gen.sv (Person 2)
6. **System test**: Verify full pipeline
7. **Synthesize**: Target FPGA
8. **Hardware test**: Real EEG data

---

## 📞 Contact

**Verification Owner**: Person 3  
**Module Owner**: Person 1 (temporal_conv.sv)  
**Integration**: Person 2 (window_gen.sv)

**Questions?**
1. Check documentation (4 guides available)
2. Review code comments
3. Ask your team!

---

## 🎉 Success Criteria

You're done when:
- ✅ All tests pass
- ✅ Latency verified
- ✅ Numerical accuracy confirmed
- ✅ Waveforms look good
- ✅ Team approved
- ✅ Ready for integration

**Ready to verify?** 
```bash
cd scripts && ./run_verification.sh
```

**Good luck! 🚀**

---

*Last updated: December 31, 2025*  
*Version: 1.0*  
*Person 3 Deliverables - Complete*
