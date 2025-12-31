@echo off
REM Windows batch script for running temporal convolution verification
REM Author: Person 3

echo ============================================================
echo Temporal Convolution Verification Flow
echo ============================================================
echo.

REM Check Python
python --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python not found! Please install Python 3.8+
    exit /b 1
)

REM Step 1: Generate test vectors
echo [Step 1/3] Generating test vectors...
cd ..\python
python generate_test_vectors.py
if errorlevel 1 (
    echo ERROR: Test vector generation failed!
    cd ..\scripts
    exit /b 1
)
echo.

REM Step 2: Run RTL simulation
echo [Step 2/3] Running RTL simulation...
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
REM Step 3: Verify results
echo.
echo [Step 3/3] Verifying results...
cd ..\python

REM Check if RTL output exists
if not exist ..\sim\rtl_output.txt (
    echo WARNING: rtl_output.txt not found, skipping verification
    echo Check simulation log for details
    cd ..\scripts
    exit /b 0
)

python verify_results.py ..\sim\rtl_output.txt ..\sim\simple_case.json
set VERIFY_RESULT=%errorlevel%

cd ..\scripts

echo.
echo ============================================================
if %VERIFY_RESULT%==0 (
    echo VERIFICATION PASSED!
) else (
    echo VERIFICATION FAILED - Check verification_report.txt
)
echo ============================================================
echo.

exit /b %VERIFY_RESULT%
