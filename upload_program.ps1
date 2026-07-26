[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$InputFile,

    [string]$Port = "COM6",

    [ValidateRange(1000, 1000000)]
    [int]$Baud = 115200,

    [ValidateRange(250, 30000)]
    [int]$TimeoutMs = 5000,

    [switch]$CaptureOutput,

    [ValidateRange(50, 30000)]
    [int]$OutputIdleTimeoutMs = 500
)

$ErrorActionPreference = "Stop"
$projectDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$inputPath = (Resolve-Path -LiteralPath $InputFile).Path
$temporaryBinary = $null
[byte[]]$capturedOutput = @()

function Get-Crc16Ccitt {
    param([byte[]]$Bytes)

    [uint32]$crc = 0xFFFF
    foreach ($value in $Bytes) {
        $crc = $crc -bxor ([uint32]$value -shl 8)
        for ($bit = 0; $bit -lt 8; $bit++) {
            if (($crc -band 0x8000) -ne 0) {
                $crc = (($crc -shl 1) -bxor 0x1021) -band 0xFFFF
            }
            else {
                $crc = ($crc -shl 1) -band 0xFFFF
            }
        }
    }
    return [uint16]$crc
}

try {
    if ([IO.Path]::GetExtension($inputPath) -ieq ".asm") {
        $buildDirectory = Join-Path $projectDirectory "build"
        [IO.Directory]::CreateDirectory($buildDirectory) | Out-Null
        $temporaryBinary = Join-Path $buildDirectory (
            [IO.Path]::GetFileNameWithoutExtension($inputPath) + ".bin"
        )
        $assembler = Join-Path $projectDirectory "tools\knot8asm.py"
        & python $assembler $inputPath -o $temporaryBinary
        if ($LASTEXITCODE -ne 0) {
            throw "Assembler failed with exit code $LASTEXITCODE."
        }
        $inputPath = $temporaryBinary
    }

    [byte[]]$payload = [IO.File]::ReadAllBytes($inputPath)
    if ($payload.Length -lt 1 -or $payload.Length -gt 4096) {
        throw "Program size must be 1..4096 bytes; got $($payload.Length)."
    }

    [byte[]]$crcInput = [byte[]]::new($payload.Length + 2)
    $crcInput[0] = [byte]($payload.Length -band 0xFF)
    $crcInput[1] = [byte](($payload.Length -shr 8) -band 0xFF)
    [Array]::Copy($payload, 0, $crcInput, 2, $payload.Length)
    [uint16]$crc = Get-Crc16Ccitt $crcInput

    [byte[]]$packet = [byte[]]::new($payload.Length + 6)
    $packet[0] = 0x4B
    $packet[1] = 0x38
    $packet[2] = $crcInput[0]
    $packet[3] = $crcInput[1]
    [Array]::Copy($payload, 0, $packet, 4, $payload.Length)
    $packet[$packet.Length - 2] = [byte]($crc -band 0xFF)
    $packet[$packet.Length - 1] = [byte](($crc -shr 8) -band 0xFF)

    $serial = [IO.Ports.SerialPort]::new(
        $Port,
        $Baud,
        [IO.Ports.Parity]::None,
        8,
        [IO.Ports.StopBits]::One
    )
    $serial.Handshake = [IO.Ports.Handshake]::None
    $serial.ReadTimeout = $TimeoutMs
    $serial.WriteTimeout = $TimeoutMs
    $serial.DtrEnable = $false
    $serial.RtsEnable = $false

    try {
        $serial.Open()
        Start-Sleep -Milliseconds 100
        $serial.DiscardInBuffer()
        Write-Host (
            "Uploading {0} bytes to {1} at {2} baud (CRC 0x{3:X4})..." -f
            $payload.Length, $Port, $Baud, $crc
        )
        $serial.Write($packet, 0, $packet.Length)
        $reply = $serial.ReadByte()

        if (($reply -eq 0x06) -and $CaptureOutput) {
            $serial.ReadTimeout = $OutputIdleTimeoutMs
            $outputBytes = [Collections.Generic.List[byte]]::new()
            while ($true) {
                try {
                    $outputBytes.Add([byte]$serial.ReadByte())
                }
                catch [TimeoutException] {
                    break
                }
            }
            $capturedOutput = $outputBytes.ToArray()
        }
    }
    finally {
        if ($null -ne $serial -and $serial.IsOpen) {
            $serial.Close()
        }
        if ($null -ne $serial) {
            $serial.Dispose()
        }
    }

    if ($reply -eq 0x06) {
        Write-Host "ACK received. CPU restarted at address 0x0000." -ForegroundColor Green
        if ($CaptureOutput) {
            $hexOutput = ($capturedOutput | ForEach-Object {
                "{0:X2}" -f $_
            }) -join " "
            $textOutput = [Text.Encoding]::ASCII.GetString($capturedOutput)
            Write-Host "Program output ($($capturedOutput.Length) bytes)"
            Write-Host "  HEX  : $hexOutput"
            Write-Host "  ASCII: $textOutput"
        }
    }
    elseif ($reply -eq 0x15) {
        throw "FPGA returned NAK (length or CRC rejected). Retry the upload."
    }
    else {
        throw ("Unexpected FPGA reply: 0x{0:X2}" -f $reply)
    }
}
catch {
    Write-Error $_
    exit 1
}
