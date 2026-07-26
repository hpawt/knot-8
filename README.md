# Knot-8 v4 FPGA Computer

Knot-8은 AliExpress `DEV190806037` Rev.C 보드의
`10CL006YE144C8G` FPGA에서 동작하는 독자 8비트 architecture다.
RISC-V 파생형이 아니며, C compiler와 tp2b 같은 작은 interpreter를
함께 실험하기 위해 설계했다.

FPGA 안에는 Knot-8 CPU, 4KiB program RAM, 16KiB data/tape/stack RAM,
board MMIO, UART program loader가 들어 있다. 공개 저장소에는 현재
Knot-8 v4와 tp2bc v0.3만 포함하며 이전 실험 버전은 로컬 archive로만
보존한다.

상세 명세:

- [Knot-8 v4 ISA](docs/KNOT8_V4_ISA.md)
- [Knot-8 C ABI](docs/KNOT8_C_ABI.md)

## 바로 사용하기

보드 USB-C를 연결하고 PowerShell에서 실행한다. 아래 `COM6`는 예시이며
실제 장치 관리자에 표시되는 port로 바꿔야 한다.

```powershell
cd <clone-path>\knot-8
.\upload_program.ps1 .\programs\knot8_v4_demo.asm `
  -Port COM6 -CaptureOutput
```

이 demo는 다음을 실제로 사용한다.

- `IDX/IDY` 두 pointer와 `SWAPXY`
- `[IDX]` byte를 증가시키는 `INC_MEM`
- `CMPI/CPCI`로 16비트 equality 확인
- LED MMIO에 `0x0B`, 즉 `1011` 출력
- UART MMIO로 문자 `K` 출력

성공 시 uploader가 FPGA ACK와 program output을 표시한다.

```text
ACK received. CPU restarted at address 0x0000.
Program output (1 bytes)
  HEX  : 4B
  ASCII: K
```

UART로 올린 program은 RAM에 있으므로 전원을 끄면 사라진다. EPCS16에
저장된 Knot-8 FPGA image와 내장 LED counter는 다음 부팅에 다시
실행된다.

## Knot-8 v4의 방향

Knot-8은 tape machine 자체가 아니라 일반 register machine이다.
다만 두 address pointer와 byte read-modify-write가 있어 C의 배열,
`memcpy`, interpreter의 source/tape pointer를 효율적으로 처리한다.

v3에서 추가된 기능:

- `IDY`: 두 번째 16비트 pointer
- `SWAPXY`: `IDX`와 `IDY`를 6 clocks에 교환
- `INC_MEM [IDX]`: memory byte 증가와 `Z/C/N/V` 갱신
- CPU UART TX MMIO
- 4KiB에서 16KiB로 확장된 data/tape/stack RAM
- `K8` UART loader magic, 기존 `R8` packet도 수신

v4에서 정합화한 기능:

- `CPC`, `CPCI`: borrow를 전달하고 sticky `Z`로 전체 equality 누적
- 16/32비트 equality, zero test, signed/unsigned ordering의 공통 chain
- reset/upload 때 16KiB data RAM을 0으로 만드는 M9K scrubber
- byte-aligned instruction을 공식 허용하는 ISA
- assembler `.align power_of_two[, fill_byte]`

기존 v1/v2/v3 opcode encoding은 모두 유지한다. 기존 `counter.asm`은
v2/v3/v4 assembler에서 byte-for-byte 동일하다.

## CPU 요약

- 8비트 data path
- 16비트 byte address
- 고정 길이 16비트 instruction
- 범용 register `R0`-`R3`
- 특수 register `PC`, `SP`, `IDX`, `IDY`
- flag `Z`, `C`, `N`, `V`
- reset vector `0x0000`
- initial empty `SP=0xC000`, descending stack
- memory-valid handshake를 지원하는 multi-cycle controller

50MHz board synchronous RAM에서:

| 종류 | clocks |
|---|---:|
| ALU, compare, branch, pointer, `SWAPXY` | 6 |
| store, `PUSH`, `PUSHI` | 8 |
| load, `POP` | 9 |
| `INC_MEM` | 10 |
| `CALL` | 9 |
| `RET` | 11 |

## 메모리 맵

| 주소 | 기능 |
|---:|---|
| `0000-0FFF` | 4KiB program/data RAM, UART loader 기록 |
| `8000-BFFF` | 16KiB global/data/tape/stack RAM |
| `FF00` | LED output, low 4 bits |
| `FF01` | button input `{6'b0,S4_n,S3_n}` |
| `FF02` | UART TX data |
| `FF03` | UART TX status, bit 0=`ready` |
| 나머지 | read `00`, write ignored |

C의 global/BSS는 `0x8000`부터 위로, stack은 `0xBFFF`부터 아래로
자란다. tp2b packed interpreter는 위쪽 8 bytes를 runtime 변수로
예약하고 `0x8000-0xBFF7`을 16,376-cell tape로 사용한다. native
backend는 16,384 cells 전체를 tape로 사용한다. hardware stack/tape
overflow 검사는 없다.

S2 reset과 새 UART program upload는 program RAM을 보존하면서 data RAM
전체를 0으로 scrub한다. CPU는 16,384 clocks 동안 reset에 유지되며
50MHz에서 지연은 약 0.328ms다. 따라서 C BSS와 tp2b tape의 시작값은
항상 0이다.

UART byte를 보낼 때는 `FF03` bit 0이 1이 될 때까지 기다린 뒤 `FF02`에
write한다. loader ACK/NAK와 CPU output은 하나의 UART transmitter를
안전하게 공유한다.

## 보드 연결

| 기능 | FPGA pin | HDL signal |
|---|---:|---|
| 50MHz oscillator | 91 | `FPGA_CLK` |
| S4, S3, S2 | 88, 89, 90 | user buttons/reset, active-low |
| CH340 RX/TX | 10, 11 | `FPGA_RX`, `FPGA_TX` |
| LED1..4 | 101, 100, 99, 98 | `LED_N[0..3]`, active-low |

LED는 4/32 duty PWM, 즉 12.5% 밝기로 구동한다. USB-C/CH340은 전원과
일반 program upload에 사용하고, 10-pin JTAG/USB-Blaster는 SOF와
EPCS16 FPGA image 갱신에만 사용한다.

## Assembler

`tools/knot8asm.py`는 label과 expression을 지원하는 2-pass
assembler다.

```powershell
python .\tools\knot8asm.py .\programs\knot8_v4_demo.asm `
  -o .\build\knot8_v4_demo.bin `
  -l .\build\knot8_v4_demo.lst
```

지원 문법:

- `;` comment, `label:`
- `.equ`, `.byte`, `.word`, `.align power_of_two[, fill_byte]`
- 숫자 `123`, `0x7B`, `$7B`, `7Bh`, `'A'`
- `symbol+constant`, `symbol-constant`
- `HIGH(expr)`, `LOW(expr)`, `HI8`, `LO8`
- relative branch label 또는 raw `-128..127`

명령어는 2 bytes지만 시작 주소는 byte-aligned다. 홀수 주소 instruction
fetch도 정상 동작한다. 특정 table/function만 정렬하려면 `.align 2`처럼
명시한다.

## tp2b compiler

`tools/tp2bc.py`는 원본 tp2b를 Knot-8으로 compile한다. 기본 `packed`
backend는 `(`, `L`, BOF, EOF를 2-bit bytecode로 저장하고 FPGA 안의
작은 interpreter가 FSM, tape, loop scan과 UART output을 실제 실행한다.

```powershell
python .\tools\tp2bc.py .\tp2b\examples\hello_worlda.tp `
  -o .\build\tp2b\hello_worlda_packed.bin `
  -S .\build\tp2b\hello_worlda_packed.asm

.\upload_program.ps1 .\build\tp2b\hello_worlda_packed.bin `
  -Port COM6 -CaptureOutput
```

7,847-command `hello_worlda.tp`는 interpreter를 포함해 2,691 bytes다.
실제 DEV190806037에서 실행해 `Hello, World!` 13 bytes를 수신했다.
작은 program용 `--backend native`와 compile-time 최적화용
`--backend const`도 유지한다. 상세 동작은
[`tp2b/README.md`](tp2b/README.md)에 있다.

## UART loader

Packet:

```text
4B 38 | length_lo length_hi | payload[length] | crc_lo crc_hi
 K  8
```

- 115200 baud, 8-N-1
- length 1..4096, little-endian
- CRC-16/CCITT-FALSE, polynomial `0x1021`, initial `0xFFFF`
- CRC 범위: length 두 bytes와 payload
- 성공 `0x06` ACK, 실패 `0x15` NAK
- legacy `52 38` (`R8`) header도 허용
- ACK는 CRC 검증과 data RAM scrub이 모두 끝난 뒤 전송

payload 안의 16비트 CPU instruction은 big-endian이다. uploader와
assembler가 protocol endian 차이를 처리한다.

## 시뮬레이션

RTL 시험에는 Icarus Verilog와 `vvp`가 필요하다. Windows portable
toolchain을 사용할 경우 다음 위치에 배치한다.

```text
tools\iverilog
```

Icarus 실행 파일과 installer cache는 저장소에 포함하지 않는다.

전체 시험:

```powershell
.\run_tests.ps1
```

시험 범위:

- 기존 v1/v2 ISA regression과 binary compatibility
- v3 `IDX/IDY`, `SWAPXY`, `INC_MEM`
- v4 `CPC/CPCI` 16/32비트 compare와 sticky equality
- stack frame, pointer, ADC/SBC, shift, signed branch
- C ABI call frame
- 4KiB program RAM과 16KiB data RAM
- reset/upload data RAM scrub
- K8 및 legacy R8 loader
- CRC ACK/NAK와 retry
- CPU UART TX MMIO와 loader transmitter arbitration
- assembler opcode, byte alignment와 `.align`
- tp2b packed/native FPGA runtime과 const whole-program backend

## Quartus와 실제 board 기록

Build:

```powershell
& 'C:\intelFPGA_lite\24.1std\quartus\bin64\quartus_sh.exe' `
  --flow compile knot8
```

휘발성 SOF:

```powershell
.\program_sof.ps1
```

EPCS16 영구 기록:

```powershell
.\program_flash.ps1
```

`program_flash.ps1`은 EPCS16 verify 후 정상 Knot-8 SOF를 FPGA에 다시
올리므로 power cycle 없이 UART loader를 바로 사용할 수 있다.

## Quartus 24.1 결과

| 항목 | RISC8 v2 | Knot-8 v3 | Knot-8 v4 |
|---|---:|---:|---:|
| 전체 logic elements | 1,274 | 1,358 | 1,398 |
| CPU logic elements | 969 | 1,011 | 1,000 |
| 전체 registers | 369 | 400 | 417 |
| CPU registers | 192 | 208 | 208 |
| memory bits | 65,536 | 163,840 | 163,840 |
| M9K blocks | 8 | 20 | 20 |
| slow 85C Fmax | 71.69MHz | 67.55MHz | 73.91MHz |
| 50MHz setup slack | +6.051ns | +5.197ns | +6.470ns |
| hold slack | +0.428ns | +0.356ns | +0.432ns |

v4의 compare chain과 reset scrubber를 포함해도 전체 logic은 v3보다
40 LE, register는 17개만 증가했다. data RAM은 계속 16개 M9K,
program RAM은 4개 M9K로 추론됐다. 실제 50MHz clock을 충분히 만족하며
setup/hold는 완전히 constrained되어 있다.

v4 bitstream은 실제 DEV190806037 Rev.C board에서 다음을 확인했다.

- JTAG ID `0x020F10DD`
- EPCS16 silicon ID `0x14`
- erase, blank-check, program, CRC verify 성공
- K8 packet으로 48-byte v4 demo upload와 ACK
- `CMPI/CPCI` 16비트 sticky equality 통과 후에만 demo가 진행
- `data_scrub_check.asm`을 연속 두 번 upload해 두 번 모두 `Z` 수신
  (첫 실행이 남긴 `0xA5`가 두 번째 upload 전에 0으로 scrub됨)
- `INC_MEM` 결과 `0x0B`가 LED `1011`로 출력
- CPU UART MMIO output `0x4B` (`K`) 수신

## 주요 파일

| 파일 | 역할 |
|---|---|
| `knot8_core.v` | Knot-8 v4 CPU |
| `knot8_board.v` | DEV190806037 top |
| `board_memory.v` | program/data RAM과 MMIO |
| `knot8.qpf`, `knot8.qsf`, `knot8.sdc` | Quartus project |
| `docs/KNOT8_V4_ISA.md` | ISA 명세 |
| `docs/KNOT8_C_ABI.md` | C ABI |
| `tools/knot8asm.py` | assembler |
| `tools/tp2bc.py` | tp2b packed/native FPGA compiler |
| `tp2b` | compiler 문서와 원본 예제 복제본 |
| `run_tests.ps1` | 전체 simulation |
| `upload_program.ps1` | K8 UART uploader/output capture |
| `program_sof.ps1`, `program_flash.ps1` | FPGA 기록 |
| `programs/knot8_v4_demo.asm` | v4 board demo |
| `releases/knot8-v4` | 현재 검증·플래시된 v4 보존본 |
| `releases/tp2bc-v0.3` | 2-bit packed FPGA runtime 보존본 |

이전 RISC8/Knot-8 및 tp2bc 릴리스는 로컬에만 보존하며 공개 저장소에는
포함하지 않는다.
