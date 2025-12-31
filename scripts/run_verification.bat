@echo off
REM Windows batch script for running temporal convolution verification

echo ============================================================
echo Temporal Convolution Verification Flow
echo ============================================================
echo.

REM Run RTL simulation
echo [Step 1/2] Running RTL simulation...

REM Store current directory
set SCRIPT_DIR=%cd%
cd /d "%~dp0\.."

REM Check for ModelSim
where vsim >nul 2>&1
if not errorlevel 1 (
    echo Using ModelSim/QuestaSim...
    cd sim
    vsim -c -do "run -all; quit" -l simulation.log temporal_conv_tb
    goto verify
)

REM Check for Icarus Verilog (including common install locations)
where iverilog >nul 2>&1
if not errorlevel 1 goto found_icarus

if exist "C:\iverilog\bin\iverilog.exe" (
    set PATH=%PATH%;C:\iverilog\bin
    goto found_icarus
)

goto no_simulator

:found_icarus
echo Using Icarus Verilog...
iverilog -g2005-sv -o sim\temporal_conv_tb.vvp sim\temporal_conv_tb.sv
if errorlevel 1 (
    echo ERROR: Compilation failed!
    cd /d "%SCRIPT_DIR%"
    exit /b 1
)
vvp sim\temporal_conv_tb.vvp | tee sim\simulation.log
goto verify

:no_simulator

:no_simulator
echo ERROR: No supported simulator found!
echo Please install ModelSim or Icarus Verilog
cd /d "%SCRIPT_DIR%"
exit /b 1

:verify
REM Step 2: Check results
echo.
echo [Step 2/2] Checking results...

REM Check if simulation log exists
if not exist sim\simulation.log (
    echo WARNING: simulation.log not found
    echo Check simulation for details
    cd /d "%SCRIPT_DIR%"
    exit /b 0
)

echo Simulation completed. Check simulation.log for test results.
cd /d "%SCRIPT_DIR%"

echo.
echo ============================================================
echo Simulation complete - Check console output for pass/fail
echo ============================================================
echo.

exit /b 0
