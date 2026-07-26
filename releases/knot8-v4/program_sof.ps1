[CmdletBinding()]
param(
    [string]$CableName,
    [ValidateRange(1, 32)]
    [int]$DeviceIndex = 1,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sofPath = Join-Path $projectRoot 'output_files\knot8.sof'
$quartusPgmCandidates = @(
    'C:\intelFPGA_lite\24.1std\quartus\bin64\quartus_pgm.exe'
)
if ($env:QUARTUS_ROOTDIR) {
    $quartusPgmCandidates +=
        (Join-Path $env:QUARTUS_ROOTDIR 'bin64\quartus_pgm.exe')
}

$quartusPgm = $quartusPgmCandidates |
    Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
    Select-Object -First 1

if (-not $quartusPgm) {
    throw 'quartus_pgm.exe를 찾지 못했습니다. Quartus Prime Programmer를 설치하거나 QUARTUS_ROOTDIR을 설정하세요.'
}

if (-not (Test-Path -LiteralPath $sofPath)) {
    throw "프로그래밍 파일이 없습니다: $sofPath`nQuartus에서 knot8 프로젝트를 먼저 컴파일하세요."
}

function Invoke-QuartusProgrammer {
    param(
        [string[]]$Arguments,
        [switch]$ShowOutput
    )

    # Some Quartus Windows builds print a harmless TBBmalloc diagnostic to
    # stderr. Capture native output and judge success by the process exit code.
    $savedErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    $nativeOutput = @(& $quartusPgm @Arguments 2>&1)
    $nativeExitCode = $LASTEXITCODE
    $ErrorActionPreference = $savedErrorActionPreference

    $cleanOutput = @(
        $nativeOutput |
            ForEach-Object { "$_" } |
            Where-Object { $_ -notmatch '^TBBmalloc:' }
    )

    if ($ShowOutput) {
        $cleanOutput | ForEach-Object { Write-Host $_ }
    }

    [PSCustomObject]@{
        ExitCode = $nativeExitCode
        Output = $cleanOutput
    }
}

$listResult = Invoke-QuartusProgrammer -Arguments @('-l')
$hardwareList = $listResult.Output
if ($listResult.ExitCode -ne 0) {
    throw "JTAG 하드웨어 검색에 실패했습니다.`n$($hardwareList -join [Environment]::NewLine)"
}

$detectedCables = @(
    $hardwareList | ForEach-Object {
        if ("$_" -match '^\s*\d+\)\s+(.+?)\s*$') {
            $Matches[1]
        }
    }
)

if (-not $CableName) {
    if ($detectedCables.Count -eq 0) {
        throw 'USB-Blaster가 감지되지 않았습니다. 보드 전원, 10핀 JTAG 방향, USB 케이블과 드라이버를 확인하세요.'
    }
    $CableName = $detectedCables[0]
}

Write-Host "Cable : $CableName"
Write-Host "SOF   : $sofPath"
Write-Host "Device: JTAG chain index $DeviceIndex"

$chainResult = Invoke-QuartusProgrammer `
    -Arguments @('-c', $CableName, '-a') `
    -ShowOutput
if ($chainResult.ExitCode -ne 0) {
    throw '선택한 JTAG 케이블의 디바이스 체인을 읽지 못했습니다.'
}

if (-not $Yes) {
    $confirmation = Read-Host '휘발성 SOF를 FPGA에 기록하려면 PROGRAM을 입력하세요'
    if ($confirmation -cne 'PROGRAM') {
        Write-Host '취소했습니다.'
        exit 0
    }
}

$operation = 'P;{0}@{1}' -f $sofPath, $DeviceIndex
$programResult = Invoke-QuartusProgrammer `
    -Arguments @('-c', $CableName, '-m', 'jtag', '-o', $operation) `
    -ShowOutput
if ($programResult.ExitCode -ne 0) {
    throw 'FPGA 프로그래밍에 실패했습니다.'
}

Write-Host '완료: LED 카운터가 동작해야 합니다. 전원을 끄면 SOF 설정은 사라집니다.'
