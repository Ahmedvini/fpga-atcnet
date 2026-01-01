# Quick Start Guide - FPGA ATCNet Verification

## 📁 Project Structure

```
fpga-atcnet/
├── rtl/                          # RTL source files
│   ├── conv/
│   │   └── temporal_conv.sv      # Temporal convolution (FIR filter)
│   └── window/
│       └── window_gen.sv         # Sliding window generator
├── sim/                          # Simulation files
│   ├── temporal_conv_tb.sv       # Testbench for temporal_conv
│   └── run_temporal_conv_tb.do   # ModelSim/QuestaSim script
├── scripts/                      # Automation scripts
│   ├── run_verification.bat      # Windows batch script
│   └── run_verification.sh       # Linux shell script
└── docs/
    └── VERIFICATION_README.md    # Detailed verification documentation
```

## 🚀 Quick Setup (Windows)

### Prerequisites

You need one of these HDL simulators:
- **ModelSim** (Intel/Altera): Professional simulator
- **Icarus Verilog**: Free open-source simulator

### Installing Icarus Verilog (Recommended for quick start)

1. Download from: http://bleyer.org/icarus/
2. Install to default location (e.g., `C:\iverilog`)
3. Add to PATH:
   - Open "Environment Variables" in Windows
   - Add `C:\iverilog\bin` to your PATH variable
4. Verify installation:
   ```powershell
   iverilog -v
   ```

### Installing ModelSim (Alternative - Professional)

1. Download Intel Quartus with ModelSim
2. Install and add to PATH:
   - Usually: `C:\intelFPGA\20.1\modelsim_ase\win32aloem`
3. Verify:
   ```powershell
   vsim -version
   ```

## ▶️ Running Verification

### Automated Flow (Recommended)

Simply run the batch script:

```powershell
cd c:\College\Graduation\FPGA\fpga-atcnet\scripts
.\run_verification.bat
```

This will:
1. Detect your installed simulator (ModelSim or Icarus)
2. Compile all RTL files + testbench
3. Run simulation
4. Display test results

### Manual Flow with ModelSim

```powershell
cd c:\College\Graduation\FPGA\fpga-atcnet\sim
vsim -do run_temporal_conv_tb.do
```

### Manual Flow with Icarus Verilog

```powershell
cd c:\College\Graduation\FPGA\fpga-atcnet
iverilog -g2012 -o tb.vvp sim/temporal_conv_tb.sv rtl/conv/temporal_conv.sv
vvp tb.vvp
```

## 📊 Understanding Test Results

### Expected Output

```
╔════════════════════════════════════════════════════════════╗
║     TEMPORAL CONVOLUTION TESTBENCH                         ║
╚════════════════════════════════════════════════════════════╝

Configuration:
  DATA_WIDTH    = 16 bits
  FRAC_BITS     = 8 bits (Q8.8)
  ...

========================================
TEST 1: Impulse Response
========================================
[PASS] Impulse test completed

========================================
TEST 2: DC Response
========================================
[PASS] DC response test completed

... (5 more tests)

╔════════════════════════════════════════════════════════════╗
║     TEST SUMMARY                                           ║
╚════════════════════════════════════════════════════════════╝

  Total tests:   7
  Passed:        7
  Failed:        0
  
  TEST PASSED ✓
```

### Test Cases Included

1. **Impulse Response**: Single 1.0 input, check FIR response
2. **DC Response**: Constant input stream
3. **Ramp Response**: Linearly increasing input
4. **Latency Measurement**: Measure cycles from input to output
5. **Streaming with Gaps**: Test valid signal handling
6. **Dilation Test**: Test dilation parameter (if > 1)
7. **Edge Cases**: Zero inputs and boundary conditions

## 🔧 Module Interfaces

### temporal_conv.sv (FIR Filter)

```systemverilog
module temporal_conv #(
    parameter int DATA_WIDTH = 16,
    parameter int KERNEL_SIZE = 5,
    parameter logic signed [15:0] COEFFS [KERNEL_SIZE] = '{default: 0}
) (
    input  logic clk,
    input  logic rst,                        // Active HIGH reset
    input  logic signed [15:0] x_in,         // Input sample
    input  logic x_valid,                    // Input valid
    output logic signed [15:0] y_out,        // Output sample
    output logic y_valid                     // Output valid
);
```

**Key Points:**
- Simple streaming interface (one sample per cycle when valid)
- Fixed-point Q8.8 format (8 integer bits, 8 fractional bits)
- Compile-time coefficients via COEFFS parameter
- 2-cycle latency from x_in to y_out

### window_gen.sv (Sliding Window)

```systemverilog
module window_gen #(
    parameter int DATA_W = 16,
    parameter int WINDOW_SIZE = 32
)(
    input  logic clk,
    input  logic rst_n,                      // Active LOW reset
    input  logic in_valid,
    input  logic [DATA_W-1:0] in_sample,
    output logic window_valid,               // High when window full
    output logic [DATA_W-1:0] window [0:WINDOW_SIZE-1]
);
```

**Key Points:**
- Accumulates samples into circular buffer
- `window_valid` goes high once WINDOW_SIZE samples collected
- Output array: `window[0]` = oldest, `window[WINDOW_SIZE-1]` = newest
- Active LOW reset

## 📝 Integrating Both Modules

To use temporal_conv with window_gen:

```systemverilog
// 1. Window generator produces sliding windows
window_gen #(
    .DATA_W(16),
    .WINDOW_SIZE(32)
) window (
    .clk(clk),
    .rst_n(rst_n),
    .in_valid(stream_valid),
    .in_sample(stream_data),
    .window_valid(win_valid),
    .window(win_data)  // Array of 32 samples
);

// 2. Feed window samples to temporal convolution
// Process each window sample through FIR filter
always_ff @(posedge clk) begin
    if (win_valid) begin
        // Send samples from window to conv filter
        conv_in <= win_data[sample_idx];
        conv_valid <= 1'b1;
    end
end

temporal_conv #(
    .KERNEL_SIZE(5),
    .COEFFS('{16'h0100, 16'h0080, 16'h0040, 16'h0020, 16'h0010})
) conv (
    .clk(clk),
    .rst(~rst_n),          // Note: opposite polarity!
    .x_in(conv_in),
    .x_valid(conv_valid),
    .y_out(conv_out),
    .y_valid(conv_out_valid)
);
```

**Important:** `temporal_conv` uses active-HIGH reset, `window_gen` uses active-LOW!

## 🐛 Troubleshooting

### "No simulator found"
- Install Icarus Verilog or ModelSim
- Add simulator to Windows PATH
- Restart PowerShell/Command Prompt

### "Cannot compile files"
- Check that RTL files exist in `rtl/conv/` and `rtl/window/`
- Verify file paths in batch script match your directory structure

### "Test fails"
- Check coefficients match expected behavior
- Verify fixed-point format (Q8.8 means values from -128 to +127.996)
- Check testbench expected values

### "Syntax errors"
- Ensure using SystemVerilog-2012 compatible simulator
- For Icarus: Use `-g2012` flag
- For ModelSim: Use `-vlog01compat` or ensure SV mode

## 📚 Next Steps

1. **Run verification** using the batch script
2. **View waveforms** (if using ModelSim with GUI)
3. **Read detailed docs** in `docs/VERIFICATION_README.md`
4. **Integrate your model** - Add Python/C++ golden reference later
5. **Create top-level** - Integrate window_gen + temporal_conv in `rtl/top.sv`

## 🎯 Development Workflow

```
1. Modify RTL (rtl/conv/temporal_conv.sv)
          ↓
2. Run verification (scripts/run_verification.bat)
          ↓
3. Check results (PASS/FAIL)
          ↓
4. View waveforms if needed (ModelSim GUI)
          ↓
5. Iterate until tests pass
```

## ⚙️ Configuration Options

Edit testbench parameters in `sim/temporal_conv_tb.sv`:

```systemverilog
parameter int DATA_WIDTH = 16;      // Change bit width
parameter int FRAC_BITS = 8;        // Q format fractional bits
parameter int KERNEL_SIZE = 4;      // FIR filter taps
parameter int SEQ_LENGTH = 32;      // Test sequence length
```

Edit FIR coefficients in DUT instantiation:

```systemverilog
test_coeffs[0] = 16'h0100; // 1.0 in Q8.8
test_coeffs[1] = 16'h0080; // 0.5 in Q8.8
// etc.
```

## 📞 Support

- **Documentation**: See `docs/VERIFICATION_README.md` for detailed info
- **RTL Questions**: Contact Person 1 (temporal_conv) or Person 2 (window_gen)

---

**Ready to verify? Run:** `scripts\run_verification.bat`
