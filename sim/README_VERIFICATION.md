# Temporal Convolution Verification Scripts
# Run these scripts to verify the RTL implementation

## Prerequisites
Before running verification:
1. Make sure you have Python 3.8+ installed
2. Install required packages:
   ```bash
   pip install numpy tensorflow keras
   ```
3. Have your RTL simulator ready (ModelSim, Verilator, etc.)

## Verification Flow

### Step 1: Generate Test Vectors
Generate golden reference test vectors from the Python TCNet model:

```bash
cd python
python generate_test_vectors.py
```

This creates:
- `../sim/simple_case.json` - Simple temporal convolution test
- `../sim/streaming_test.json` - Streaming input test
- `../sim/tcn_block.json` - Full TCN block test
- `../sim/test_config.json` - Configuration file
- `../sim/test_params.svh` - SystemVerilog parameter file

### Step 2: Run RTL Simulation
Run the testbench with your simulator:

#### Using ModelSim/QuestaSim:
```bash
cd sim
vsim -do run_temporal_conv_tb.do
```

#### Using Verilator:
```bash
cd sim
verilator --cc --exe --build temporal_conv_tb.sv temporal_conv.sv
./obj_dir/Vtemporal_conv_tb
```

#### Using Icarus Verilog:
```bash
cd sim
iverilog -g2012 -o temporal_conv_tb.vvp temporal_conv_tb.sv temporal_conv.sv
vvp temporal_conv_tb.vvp
```

### Step 3: Verify Results
Compare RTL outputs with golden reference:

```bash
cd python
python verify_results.py ../sim/rtl_output.txt ../sim/simple_case.json
```

Options:
- Add tolerance as 3rd argument: `python verify_results.py ... ... 3`
- Default tolerance is 2 LSB

## Automated Full Verification

Use the master script to run everything:

```bash
# Windows
.\scripts\run_verification.bat

# Linux/Mac
./scripts/run_verification.sh
```

## Output Files

After running verification, check these files:
- `sim/temporal_conv_tb.vcd` - Waveform dump
- `sim/rtl_output.txt` - RTL simulation results  
- `verification_report.txt` - Detailed comparison report
- `sim/temporal_conv_tb.log` - Simulation log

## Interpreting Results

### Success Indicators
- ✓ "TEST PASSED" in testbench output
- ✓ "VERIFICATION PASSED" from verify_results.py
- ✓ 100% pass rate in verification report
- ✓ All latency measurements match expected values

### Common Issues

#### Latency Mismatch
- **Symptom**: "Latency mismatch!" in testbench
- **Check**: Pipeline stages in temporal_conv.sv
- **Expected**: Latency = KERNEL_SIZE cycles for causal padding

#### Numerical Errors
- **Symptom**: Value mismatches > tolerance
- **Check**: Fixed-point arithmetic in conv module
- **Fix**: Verify MAC accumulator bit width, rounding
- **Tolerance**: ±2 LSB is acceptable for Q8.8 format

#### Valid Signal Issues  
- **Symptom**: "Expected valid output" errors
- **Check**: Valid propagation through pipeline
- **Fix**: Verify shift register and valid logic

#### Dimension Mismatch
- **Symptom**: "dimension_mismatch" in report
- **Check**: Channel counts match between testbench and DUT
- **Fix**: Update parameters in temporal_conv_tb.sv

## Debug Tips

### View Waveforms
```bash
gtkwave sim/temporal_conv_tb.vcd
```

Key signals to check:
- `data_in_valid` - Input valid signal
- `data_out_valid` - Output valid signal  
- `kernel_weights` - Weight loading
- Internal shift registers
- MAC accumulator

### Enable Verbose Output
In temporal_conv_tb.sv, add:
```systemverilog
initial begin
    $display("Verbose output enabled");
    // Add more $display statements
end
```

### Single Test Debug
Comment out tests in main sequence to run one at a time:
```systemverilog
// test_impulse_response();
// test_dc_response();
test_ramp_response();  // Run only this one
```

## Performance Metrics

The verification checks:

1. **Cycle-Accurate Latency**
   - First valid output timing
   - Pipeline depth verification
   - Throughput measurement

2. **Numerical Correctness**
   - Fixed-point accuracy (±2 LSB)
   - Overflow detection
   - Edge case handling

3. **Protocol Compliance**
   - Valid signal behavior
   - Ready/valid handshake (if used)
   - Streaming data handling

## Test Coverage

Current test cases cover:
- ✓ Impulse response (basic functionality)
- ✓ DC response (constant inputs)
- ✓ Ramp response (linearity)
- ✓ Latency measurement
- ✓ Streaming with gaps (valid control)
- ✓ Edge cases (zeros, boundaries)
- ⚠ Dilation (if DILATION > 1)
- ⚠ Multi-rate (future work)

## Next Steps

After passing basic tests:
1. Integrate with window_gen.sv
2. Test full TCN block (multiple layers)
3. Test with real EEG data
4. Performance/timing analysis
5. FPGA synthesis and place & route

## Questions?

Contact: Person 3 (Verification Lead)
