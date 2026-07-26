[CmdletBinding()]
param(
    [string]$CableName,

    [ValidateRange(1, 32)]
    [int]$DeviceIndex = 1,

    [switch]$Yes
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sofPath = Join-Path $projectRoot "output_files\knot8.sof"
$jicPath = Join-Path $projectRoot "output_files\knot8.jic"

$quartusRoots = @("C:\intelFPGA_lite\24.1std\quartus")
if ($env:QUARTUS_ROOTDIR) {
    $quartusRoots += $env:QUARTUS_ROOTDIR
}
$quartusRoot = $quartusRoots |
    Where-Object {
        $_ -and
        (Test-Path -LiteralPath (Join-Path $_ "bin64\quartus_pgm.exe")) -and
        (Test-Path -LiteralPath (Join-Path $_ "bin64\quartus_cpf.exe"))
    } |
    Select-Object -First 1

if (-not $quartusRoot) {
    throw "quartus_pgm.exe와 quartus_cpf.exe를 찾지 못했습니다."
}
if (-not (Test-Path -LiteralPath $sofPath)) {
    throw "SOF가 없습니다. Quartus 프로젝트를 먼저 컴파일하세요: $sofPath"
}

$quartusPgm = Join-Path $quartusRoot "bin64\quartus_pgm.exe"
$quartusCpf = Join-Path $quartusRoot "bin64\quartus_cpf.exe"

function Invoke-NativeChecked {
    param(
        [string]$Executable,
        [string[]]$Arguments
    )

    $savedPreference = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    $output = @(& $Executable @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $savedPreference

    $output |
        ForEach-Object { "$_" } |
        Where-Object { $_ -notmatch "^TBBmalloc:" } |
        ForEach-Object { Write-Host $_ }

    if ($exitCode -ne 0) {
        throw "$([IO.Path]::GetFileName($Executable)) failed with exit code $exitCode."
    }
}

if (-not $CableName) {
    $savedPreference = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    $hardwareList = @(& $quartusPgm -l 2>&1)
    $listExitCode = $LASTEXITCODE
    $ErrorActionPreference = $savedPreference
    if ($listExitCode -ne 0) {
        throw "JTAG 케이블 검색에 실패했습니다."
    }
    $CableName = $hardwareList |
        ForEach-Object {
            if ("$_" -match "^\s*\d+\)\s+(.+?)\s*$") {
                $Matches[1]
            }
        } |
        Select-Object -First 1
}
if (-not $CableName) {
    throw "USB-Blaster를 찾지 못했습니다."
}

Write-Host "Cable: $CableName"
Write-Host "SOF  : $sofPath"
Write-Host "JIC  : $jicPath"
Write-Host "Flash: EPCS16"

if (-not $Yes) {
    $confirmation = Read-Host (
        "EPCS16을 지우고 새 FPGA 이미지를 영구 기록하려면 FLASH를 입력하세요"
    )
    if ($confirmation -cne "FLASH") {
        Write-Host "취소했습니다."
        exit 0
    }
}

Invoke-NativeChecked $quartusCpf @(
    "-c", "-d", "EPCS16", "-s", "10CL006Y", $sofPath, $jicPath
)

$operation = "PVBI;{0}@{1}" -f $jicPath, $DeviceIndex
Invoke-NativeChecked $quartusPgm @(
    "-c", $CableName, "-m", "jtag", "-o", $operation
)

# The JIC operation temporarily leaves the FPGA running the Serial Flash
# Loader image. Re-load the normal design so UART programming is available
# immediately without requiring a board power cycle.
$sofOperation = "P;{0}@{1}" -f $sofPath, $DeviceIndex
Invoke-NativeChecked $quartusPgm @(
    "-c", $CableName, "-m", "jtag", "-o", $sofOperation
)

Write-Host (
    "완료: EPCS16 기록과 현재 FPGA 재설정을 마쳤습니다. UART 로더/CPU가 지금 동작하며 전원을 다시 넣어도 자동 부팅합니다."
) -ForegroundColor Green
