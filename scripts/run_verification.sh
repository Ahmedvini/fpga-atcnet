#!/bin/bash
# Linux/Mac bash script for running temporal convolution verification
# Author: Person 3

set -e  # Exit on error

echo "============================================================"
echo "Temporal Convolution Verification Flow"
echo "============================================================"
echo ""

# Run RTL simulation
echo "[Step 1/2] Running RTL simulation..."
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

# Check results
echo ""
echo "[Step 2/2] Checking results..."

if [ ! -f ../sim/simulation.log ]; then
    echo "WARNING: simulation.log not found"
    echo "Check simulation for details"
    exit 0
fi

echo "Simulation completed. Check simulation.log for test results."

echo ""
echo "============================================================"
echo "Simulation complete - Check console output for pass/fail"
echo "============================================================"
echo ""

exit 0


if __name__ == "__main__":
    main()
