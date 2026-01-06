
param(
    [Parameter(Position=0)]
    [ValidateSet("temporal", "top", "all", "help")]
    [string]$TestName = "help"
)

#Define the project root directory

$ProjectRoot = "C:\College\Graduation\FPGA\fpga-atcnet"

function Show-Help {
    Write-Host ""
    Write-Host "ATCNet Vivado Test Runner" -ForegroundColor Cyan
    Write-Host "=========================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  .\run_vivado_tests.ps1 [test_name]"
    Write-Host ""
    Write-Host "Available Tests:" -ForegroundColor Yellow
    Write-Host "  temporal  - Run temporal_conv unit test"
    Write-Host "  top       - Run top-level integration test"
    Write-Host "  all       - Run comprehensive test suite (all modules)"
    Write-Host "  help      - Show this help message"
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  .\run_vivado_tests.ps1 temporal"
    Write-Host "  .\run_vivado_tests.ps1 top"
    Write-Host "  .\run_vivado_tests.ps1 all"
    Write-Host ""
}

function Run-TemporalTest {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Green
    Write-Host "Running Temporal Conv Unit Test" -ForegroundColor Green
    Write-Host "================================================" -ForegroundColor Green
    Write-Host ""
    
    Push-Location $ProjectRoot
    
    Write-Host "[1/3] Compiling RTL and testbench..." -ForegroundColor Yellow
    xvlog --sv rtl/conv/temporal_conv.sv sim/temporal_conv_tb.sv
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Compilation failed!" -ForegroundColor Red
        Pop-Location
        return
    }
    
    Write-Host "[2/3] Elaborating design..." -ForegroundColor Yellow
    xelab temporal_conv_tb -debug typical
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Elaboration failed!" -ForegroundColor Red
        Pop-Location
        return
    }
    
    Write-Host "[3/3] Running simulation..." -ForegroundColor Yellow
    xsim temporal_conv_tb -runall
    
    Pop-Location
    Write-Host ""
    Write-Host "Test completed!" -ForegroundColor Green
}

function Run-TopTest {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Green
    Write-Host "Running Top-Level Integration Test" -ForegroundColor Green
    Write-Host "================================================" -ForegroundColor Green
    Write-Host ""
    
    Push-Location $ProjectRoot
    
    Write-Host "[1/3] Compiling RTL and testbench..." -ForegroundColor Yellow
    xvlog --sv rtl/conv/temporal_conv.sv `
                 rtl/conv/dual_branch_conv.sv `
                 rtl/conv/channel_scale.sv `
                 rtl/window/window_gen.sv `
                 rtl/window/window_reader.sv `
                 rtl/top.sv `
                 sim/top_tb.sv
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Compilation failed!" -ForegroundColor Red
        Pop-Location
        return
    }
    
    Write-Host "[2/3] Elaborating design..." -ForegroundColor Yellow
    xelab top_tb -debug typical
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Elaboration failed!" -ForegroundColor Red
        Pop-Location
        return
    }
    
    Write-Host "[3/3] Running simulation..." -ForegroundColor Yellow
    xsim top_tb -runall
    
    Pop-Location
    Write-Host ""
    Write-Host "Test completed!" -ForegroundColor Green
}

function Run-AllTests {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Green
    Write-Host "Running Comprehensive Test Suite (All Modules)" -ForegroundColor Green
    Write-Host "================================================" -ForegroundColor Green
    Write-Host ""
    
    Push-Location $ProjectRoot
    
    Write-Host "[1/3] Compiling all RTL and testbench..." -ForegroundColor Yellow
    xvlog --sv rtl/conv/temporal_conv.sv `
                 rtl/conv/dual_branch_conv.sv `
                 rtl/conv/channel_scale.sv `
                 rtl/window/window_gen.sv `
                 rtl/window/window_reader.sv `
                 rtl/conv/spatial_conv_serial_stream.sv `
                 rtl/fusion/temporal_fusion.sv `
                 rtl/attention/temporal_multihead_attention.sv `
                 sim/all_modules_tb.sv
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Compilation failed!" -ForegroundColor Red
        Pop-Location
        return
    }
    
    Write-Host "[2/3] Elaborating design..." -ForegroundColor Yellow
    xelab all_modules_tb -debug typical
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Elaboration failed!" -ForegroundColor Red
        Pop-Location
        return
    }
    
    Write-Host "[3/3] Running simulation..." -ForegroundColor Yellow
    xsim all_modules_tb -runall
    
    Pop-Location
    Write-Host ""
    Write-Host "Test completed!" -ForegroundColor Green
}

# Main execution
switch ($TestName) {
    "temporal" { Run-TemporalTest }
    "top"      { Run-TopTest }
    "all"      { Run-AllTests }
    "help"     { Show-Help }
    default    { Show-Help }
}
