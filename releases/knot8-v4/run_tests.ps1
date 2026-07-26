[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sharedRoot = Split-Path -Parent (Split-Path -Parent $projectRoot)
$iverilogRoot = @(
    (Join-Path $projectRoot "tools\iverilog"),
    (Join-Path $sharedRoot "tools\iverilog")
) |
    Where-Object {
        Test-Path -LiteralPath (Join-Path $_ "bin\iverilog.exe")
    } |
    Select-Object -First 1

if (-not $iverilogRoot) {
    throw "고정 Icarus 도구를 project 또는 shared tools 경로에서 찾지 못했습니다."
}

$iverilog = Join-Path $iverilogRoot "bin\iverilog.exe"
$vvp = Join-Path $iverilogRoot "bin\vvp.exe"
$buildDirectory = Join-Path $projectRoot "build\simulation"

[IO.Directory]::CreateDirectory($buildDirectory) | Out-Null

$commonBoardSources = @(
    (Join-Path $projectRoot "knot8_core.v"),
    (Join-Path $projectRoot "board_memory.v"),
    (Join-Path $projectRoot "uart_rx.v"),
    (Join-Path $projectRoot "uart_tx.v"),
    (Join-Path $projectRoot "uart_program_loader.v"),
    (Join-Path $projectRoot "knot8_board.v")
)

$tests = @(
    [PSCustomObject]@{
        Name = "knot8_core_tb"
        Sources = @(
            (Join-Path $projectRoot "knot8_core.v"),
            (Join-Path $projectRoot "knot8_core_tb.sv")
        )
    },
    [PSCustomObject]@{
        Name = "knot8_board_tb"
        Sources = $commonBoardSources + @(
            (Join-Path $projectRoot "knot8_board_tb.sv")
        )
    },
    [PSCustomObject]@{
        Name = "uart_loader_tb"
        Sources = $commonBoardSources + @(
            (Join-Path $projectRoot "uart_loader_tb.sv")
        )
    }
)

foreach ($test in $tests) {
    $output = Join-Path $buildDirectory "$($test.Name).vvp"
    Write-Host "Compile: $($test.Name)"
    & $iverilog -g2012 -s $test.Name -o $output @($test.Sources)
    if ($LASTEXITCODE -ne 0) {
        throw "Icarus compile failed: $($test.Name)"
    }

    Write-Host "Run    : $($test.Name)"
    & $vvp $output
    if ($LASTEXITCODE -ne 0) {
        throw "Simulation failed: $($test.Name)"
    }
}

Write-Host "Run    : knot8 assembler tests"
& python (Join-Path $projectRoot "tools\test_knot8asm.py")
if ($LASTEXITCODE -ne 0) {
    throw "Assembler tests failed"
}

Write-Host "All Knot-8 v4 simulations and assembler tests passed." -ForegroundColor Green
