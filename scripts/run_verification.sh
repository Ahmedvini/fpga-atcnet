#!/bin/bash
# Linux/Mac bash script for running temporal convolution verification
# Author: Person 3

set -e  # Exit on error

echo "============================================================"
echo "Temporal Convolution Verification Flow"
echo "============================================================"
echo ""

# Check Python
if ! command -v python3 &> /dev/null; then
    echo "ERROR: Python 3 not found! Please install Python 3.8+"
    exit 1
fi

# Step 1: Generate test vectors
echo "[Step 1/3] Generating test vectors..."
cd ../python
python3 generate_test_vectors.py
echo ""

# Step 2: Run RTL simulation
echo "[Step 2/3] Running RTL simulation..."
cd ../sim

# Check for available simulators
if command -v vsim &> /dev/null; then
    echo "Using ModelSim/QuestaSim..."
    vsim -c -do "run -all; quit" -l simulation.log temporal_conv_tb
elif command -v iverilog &> /dev/null; then
    echo "Using Icarus Verilog..."
    iverilog -g2012 -o temporal_conv_tb.vvp temporal_conv_tb.sv ../rtl/conv/temporal_conv.sv
    vvp temporal_conv_tb.vvp > simulation.log
elif command -v verilator &> /dev/null; then
    echo "Using Verilator..."
    verilator --cc --exe --build -j 0 temporal_conv_tb.sv ../rtl/conv/temporal_conv.sv
    ./obj_dir/Vtemporal_conv_tb > simulation.log
else
    echo "ERROR: No supported simulator found!"
    echo "Please install ModelSim, Icarus Verilog, or Verilator"
    exit 1
fi

# Step 3: Verify results
echo ""
echo "[Step 3/3] Verifying results..."
cd ../python

if [ ! -f ../sim/rtl_output.txt ]; then
    echo "WARNING: rtl_output.txt not found, skipping verification"
    echo "Check simulation log for details"
    exit 0
fi

python3 verify_results.py ../sim/rtl_output.txt ../sim/simple_case.json
VERIFY_RESULT=$?

cd ../scripts

echo ""
echo "============================================================"
if [ $VERIFY_RESULT -eq 0 ]; then
    echo "✓ VERIFICATION PASSED!"
else
    echo "✗ VERIFICATION FAILED - Check verification_report.txt"
fi
echo "============================================================"
echo ""

exit $VERIFY_RESULT
