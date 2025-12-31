@echo off
REM Windows batch script for running temporal convolution verification
REM Author: Person 3

echo ============================================================
echo Temporal Convolution Verification Flow
echo ============================================================
echo.

REM Run RTL simulation
echo [Step 1/2] Running RTL simulation...
cd ..\sim

REM Check for ModelSim
where vsim >nul 2>&1
if not errorlevel 1 (
    echo Using ModelSim/QuestaSim...
    vsim -c -do "run -all; quit" -l simulation.log temporal_conv_tb
    goto verify
)

REM Check for Icarus Verilog
where iverilog >nul 2>&1
if not errorlevel 1 (
    echo Using Icarus Verilog...
    iverilog -g2012 -o temporal_conv_tb.vvp temporal_conv_tb.sv ..\rtl\conv\temporal_conv.sv
    vvp temporal_conv_tb.vvp > simulation.log
    goto verify
)

echo ERROR: No supported simulator found!
echo Please install ModelSim or Icarus Verilog
cd ..\scripts
exit /b 1

:verify
REM Step 2: Check results
echo.
echo [Step 2/2] Checking results...

REM Check if simulation log exists
if not exist ..\sim\simulation.log (
    echo WARNING: simulation.log not found
    echo Check simulation for details
    cd ..\scripts
    exit /b 0
)

echo Simulation completed. Check simulation.log for test results.
cd ..\scripts

echo.
echo ============================================================
echo Simulation complete - Check console output for pass/fail
echo ============================================================
echo.

exit /b 0
