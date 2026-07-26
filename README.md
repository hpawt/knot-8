# Knot-8

Knot-8 is a custom 8-bit CPU implemented on the Cyclone 10 LP
`10CL006YE144C8G` FPGA found on the `DEV190806037` Rev.C board. The FPGA
design includes the CPU, memory, MMIO, and a UART program loader.

## Overview

- 8-bit data path and 16-bit address space
- Four general-purpose registers: `R0`-`R3`
- Special registers: `PC`, `SP`, `IDX`, and `IDY`
- `Z`, `C`, `N`, and `V` flags
- 4 KiB program RAM
- 16 KiB data, tape, and stack RAM
- LED, button, and UART MMIO
- Program upload over USB-C at 115200 baud

Architecture documentation:

- [Knot-8 v4 ISA](docs/KNOT8_V4_ISA.md)
- [Knot-8 C ABI](docs/KNOT8_C_ABI.md)

## Running a program

Connect the board over USB-C and find its CH340 serial port. `COM6` is used
below as an example.

```powershell
.\upload_program.ps1 .\programs\knot8_v4_demo.asm `
  -Port COM6 -CaptureOutput
```

The demo displays `1011` on the LEDs and sends `K` over UART.

```text
ACK received. CPU restarted at address 0x0000.
Program output (1 bytes)
  HEX  : 4B
  ASCII: K
```

Uploaded programs are stored in RAM and do not survive a power cycle.

## Assembler

```powershell
python .\tools\knot8asm.py .\programs\knot8_v4_demo.asm `
  -o .\build\knot8_v4_demo.bin `
  -l .\build\knot8_v4_demo.lst
```

`tools/knot8asm.py` is a two-pass assembler with labels, expressions, `.equ`,
`.byte`, `.word`, and `.align`.

## tp2b

`tools/tp2bc.py` compiles tp2b programs for Knot-8. Its default `packed`
backend stores instructions as 2-bit bytecode. The FSM, tape, loop scanning,
and output all execute on the FPGA.

```powershell
python .\tools\tp2bc.py .\tp2b\examples\hello_worlda.tp `
  -o .\build\tp2b\hello_worlda.bin

.\upload_program.ps1 .\build\tp2b\hello_worlda.bin `
  -Port COM6 -CaptureOutput
```

A 7,847-command tp2b program was verified on the physical board:

```text
Hello, World!
```

See [tp2b/README.md](tp2b/README.md) for backend details.

## Tests

On Windows, place a portable Icarus Verilog toolchain in `tools\iverilog`,
then run:

```powershell
.\run_tests.ps1
```

The test suite covers:

- CPU instructions and 16/32-bit comparisons
- Stack, memory, and dual address pointers
- Board RAM, MMIO, and reset scrubbing
- UART loading, CRC validation, and CPU restart
- The assembler and tp2b compiler

## FPGA build

Build with Quartus Prime Lite 24.1:

```powershell
& 'C:\intelFPGA_lite\24.1std\quartus\bin64\quartus_sh.exe' `
  --flow compile knot8
```

Program the board:

```powershell
.\program_sof.ps1
.\program_flash.ps1
```

The verified v4 build uses 1,398 logic elements and 20 M9K blocks, reaches
73.91 MHz Fmax, and meets setup and hold timing at the board's 50 MHz clock.

## Project layout

| Path | Description |
|---|---|
| `knot8_core.v` | CPU core |
| `knot8_board.v` | Board top level |
| `board_memory.v` | RAM and MMIO |
| `docs/` | ISA and ABI documentation |
| `programs/` | Example programs |
| `tools/knot8asm.py` | Assembler |
| `tools/tp2bc.py` | tp2b compiler |
| `upload_program.ps1` | UART uploader |
