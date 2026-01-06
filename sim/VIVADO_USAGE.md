# Vivado Testbench Usage Guide

## Overview
All testbenches in this directory are now fully compatible with Vivado Simulator (xsim). They use SystemVerilog 2012 features that Vivado supports natively.

## Testbench Files

### 1. temporal_conv_tb.sv
- **Purpose**: Unit test for temporal_conv FIR filter module
- **Features**: 6 comprehensive tests (impulse, DC, ramp, zeros, latency, valid gaps)
- **Compatibility**: Verilog-2001 syntax for maximum compatibility

### 2. top_tb.sv
- **Purpose**: Integration test for complete ATCNet pipeline
- **Tests**: Window generation → reading → dual branch → channel scale
- **SystemVerilog**: Uses `parameter int`, `logic`, array initialization

### 3. all_modules_tb.sv
- **Purpose**: Comprehensive test suite for all 8 ATCNet modules
- **Modules**: temporal_conv, dual_branch_conv, channel_scale, window_gen, window_reader, spatial_conv, temporal_fusion, attention
- **Architecture**: All DUTs instantiated at module level (Vivado requirement)

## Running Tests in Vivado

### Method 1: Vivado GUI (Recommended for Debugging)

#### Step 1: Open Vivado
```bash
vivado
```

#### Step 2: Create Project or Use TCL Console
In TCL Console:

```tcl
# Set working directory
cd C:/College/Graduation/FPGA/fpga-atcnet

# Compile RTL files
read_verilog -sv rtl/conv/temporal_conv.sv
read_verilog -sv sim/temporal_conv_tb.sv

# Elaborate design
synth_design -top temporal_conv_tb -part xc7a35ticsg324-1L

# Launch simulator
launch_simulation

# Add waves
add_wave /*

# Run simulation
run 500us

# View waveform
start_gui
```

#### Step 3: For Integration Test (top_tb.sv)
```tcl
# Compile all RTL files
read_verilog -sv rtl/conv/temporal_conv.sv
read_verilog -sv rtl/conv/dual_branch_conv.sv
read_verilog -sv rtl/conv/channel_scale.sv
read_verilog -sv rtl/window/window_gen.sv
read_verilog -sv rtl/window/window_reader.sv
read_verilog -sv rtl/top.sv
read_verilog -sv sim/top_tb.sv

# Elaborate and simulate
synth_design -top top_tb -part xc7a35ticsg324-1L
launch_simulation
add_wave /*
run 1ms
```

#### Step 4: For All Modules Test
```tcl
# Compile ALL RTL modules
read_verilog -sv rtl/conv/temporal_conv.sv
read_verilog -sv rtl/conv/dual_branch_conv.sv
read_verilog -sv rtl/conv/channel_scale.sv
read_verilog -sv rtl/window/window_gen.sv
read_verilog -sv rtl/window/window_reader.sv
read_verilog -sv rtl/conv/spatial_conv_serial_stream.sv
read_verilog -sv rtl/fusion/temporal_fusion.sv
read_verilog -sv rtl/attention/temporal_multihead_attention.sv
read_verilog -sv sim/all_modules_tb.sv

# Elaborate and simulate
synth_design -top all_modules_tb -part xc7a35ticsg324-1L
launch_simulation
add_wave /*
run 2ms
```

### Method 2: Command Line (Faster for Quick Tests)

#### Temporal Conv Test
```bash
cd C:/College/Graduation/FPGA/fpga-atcnet

# Compile
xvlog --sv rtl/conv/temporal_conv.sv sim/temporal_conv_tb.sv

# Elaborate  
xelab temporal_conv_tb -debug typical

# Run
xsim temporal_conv_tb -runall
```

#### Top Integration Test
```bash
# Compile all dependencies
xvlog --sv rtl/conv/temporal_conv.sv ^
             rtl/conv/dual_branch_conv.sv ^
             rtl/conv/channel_scale.sv ^
             rtl/window/window_gen.sv ^
             rtl/window/window_reader.sv ^
             rtl/top.sv ^
             sim/top_tb.sv

# Elaborate
xelab top_tb -debug typical

# Run
xsim top_tb -runall
```

#### All Modules Test
```bash
# Compile everything
xvlog --sv rtl/conv/temporal_conv.sv ^
             rtl/conv/dual_branch_conv.sv ^
             rtl/conv/channel_scale.sv ^
             rtl/window/window_gen.sv ^
             rtl/window/window_reader.sv ^
             rtl/conv/spatial_conv_serial_stream.sv ^
             rtl/fusion/temporal_fusion.sv ^
             rtl/attention/temporal_multihead_attention.sv ^
             sim/all_modules_tb.sv

# Elaborate
xelab all_modules_tb -debug typical

# Run
xsim all_modules_tb -runall
```

### Method 3: TCL Script (Automated)

Create file `run_tests.tcl`:
```tcl
# Temporal Conv Test
puts "========================================="
puts "Running temporal_conv_tb"
puts "========================================="
read_verilog -sv rtl/conv/temporal_conv.sv
read_verilog -sv sim/temporal_conv_tb.sv
synth_design -top temporal_conv_tb -part xc7a35ticsg324-1L
launch_simulation
run 500us
close_sim

# Top Integration Test
puts "========================================="
puts "Running top_tb"
puts "========================================="
read_verilog -sv rtl/conv/temporal_conv.sv
read_verilog -sv rtl/conv/dual_branch_conv.sv
read_verilog -sv rtl/conv/channel_scale.sv
read_verilog -sv rtl/window/window_gen.sv
read_verilog -sv rtl/window/window_reader.sv
read_verilog -sv rtl/top.sv
read_verilog -sv sim/top_tb.sv
synth_design -top top_tb -part xc7a35ticsg324-1L
launch_simulation
run 1ms
close_sim

puts "========================================="
puts "All tests completed!"
puts "========================================="
```

Run with:
```bash
vivado -mode batch -source run_tests.tcl
```

## Waveform Viewing

### Vivado Waveform Viewer (Built-in)
- Automatically opens when you run `launch_simulation` in GUI mode
- Add signals: Right-click → Add to Wave Window
- Save waveform configuration: File → Save Wave Configuration

### GTKWave (Alternative)
If you prefer GTKWave, you can add VCD dumping back to testbenches:

1. Add to testbench initial block:
```systemverilog
initial begin
    $dumpfile("testbench_name.vcd");
    $dumpvars(0, testbench_name);
end
```

2. Run simulation to generate VCD
3. Open in GTKWave:
```bash
gtkwave testbench_name.vcd
```

## Common Issues

### Issue 1: "Cannot find module"
**Solution**: Make sure all RTL files are compiled before the testbench
```tcl
# Compile RTL first, testbench second
read_verilog -sv rtl/conv/temporal_conv.sv
read_verilog -sv sim/temporal_conv_tb.sv  # This depends on temporal_conv
```

### Issue 2: "Unsupported SystemVerilog construct"
**Solution**: All testbenches use Vivado-supported SystemVerilog. If you see this:
- Check Vivado version (2019.1+ recommended)
- Use `-sv` flag when compiling: `xvlog --sv file.sv`

### Issue 3: "Array parameter type mismatch"
**Solution**: Already fixed! All array parameters use proper SystemVerilog syntax:
```systemverilog
parameter logic signed [15:0] COEFFS [0:4] = '{16'h0100, 16'h0080, ...};
```

### Issue 4: Waveform not showing
**Solution**: 
- In GUI: Make sure you ran `add_wave /*` before `run`
- In batch: Use `-debug typical` flag in xelab
- Check simulation actually ran: look for `$finish` in console output

## Expected Output

### Temporal Conv Test (Success)
```
========================================
ATCNet Temporal Convolution Testbench
========================================
Testing actual temporal_conv.sv RTL

TEST 1: Impulse Response
...
  ✓ PASS - Impulse response correct
...
  ALL TESTS PASSED!
  temporal_conv.sv is VERIFIED
```

### Top Integration Test (Success)
```
========================================
ATCNet Top-Level Integration Testbench
========================================

TEST 1: End-to-End Data Flow
...
  ✓ PASS - Pipeline functioning correctly
...
  ✓ ALL TESTS PASSED!
```

### All Modules Test (Success)
```
========================================
MODULE TEST 1: temporal_conv
========================================
  Sending impulse...
  [PASS] temporal_conv test completed

MODULE TEST 2: dual_branch_conv
========================================
  [PASS] dual_branch_conv test completed
...
  ✓ ALL MODULE TESTS PASSED!
  ✓ Ready for integration testing
```

## Performance Tips

1. **Use Batch Mode** for quick regression testing:
   ```bash
   vivado -mode batch -source run_tests.tcl
   ```

2. **Parallel Compilation**: Vivado can compile multiple files in parallel:
   ```tcl
   set_param general.maxThreads 8
   ```

3. **Incremental Compilation**: After first run, only recompile changed files

4. **Waveform Optimization**: Only add signals you need to view:
   ```tcl
   add_wave /testbench/dut/*  # Only DUT signals, not entire testbench
   ```

## Next Steps

1. ✅ All testbenches are Vivado-compatible
2. Run individual module tests first (temporal_conv_tb.sv)
3. Run integration test (top_tb.sv)
4. Run comprehensive suite (all_modules_tb.sv)
5. Analyze waveforms for any unexpected behavior
6. Proceed to synthesis if all tests pass

## Contact

If you encounter issues:
- Check Vivado log files in `vivado.log`
- Look for ERROR/CRITICAL_WARNING messages
- Verify all RTL files exist in correct directories
