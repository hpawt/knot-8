# Knot-8 v4 known-good release

2026-07-26에 DEV190806037 Rev.C (`10CL006YE144C8G`)에서 검증하고
EPCS16에 기록한 Knot-8 v4 보존본이다. 이전 RISC8/Knot-8 실험 버전은
공개 저장소에 포함하지 않는다.

## v4 변경

- `CPC Rd,Rs` (`0x2E`)와 `CPCI Rd,u8` (`0x1E`)
- borrow 전달과 sticky `Z`를 이용한 정확한 16/32비트 compare/zero test
- reset 및 UART upload 때 16KiB data RAM 전체를 0으로 만드는 scrubber
- byte-aligned instruction 공식 지원
- assembler `.align power_of_two[, fill_byte]`

명세는 `docs/KNOT8_V4_ISA.md`, ABI는 `docs/KNOT8_C_ABI.md`에 있다.

## 검증 결과

- 모든 core/board/UART simulation 통과
- assembler opcode/alignment regression 4개 통과
- Quartus 24.1 full compile: 0 errors, 2 board-level warnings
- 1,398 logic elements, 417 registers, 20 M9Ks
- slow 85C Fmax 73.91MHz
- 50MHz setup slack +6.470ns, hold slack +0.432ns
- v4 demo 48 bytes, CRC `0x45F7`, 실제 UART output `K`
- data scrub diagnostic 연속 두 번 실제 UART output `Z`
- EPCS16 erase/program/CRC verify 성공

## 사용

RTL 시험용 Icarus portable toolchain은 project root의
`tools\iverilog`에 별도로 배치한다. toolchain binary는 이 release에
포함하지 않는다.

```powershell
.\run_tests.ps1
.\upload_program.ps1 .\programs\knot8_v4_demo.asm `
  -Port COM6 -CaptureOutput
```

`hardware/knot8-v4.sof`는 휘발성 FPGA 설정, `hardware/knot8-v4.jic`는
EPCS16 영구 기록 이미지다. release root의 programming script는
`output_files/knot8.sof`와 `output_files/knot8.jic`를 직접 사용한다.

```text
SHA-256 knot8-v4.sof
A99A1A7358EE7B3B02D7D04A89EDADAD856E2345DB31E7FF1FD9DB20B4F3069D

SHA-256 knot8-v4.jic
4FD1776FFFE350AFB60C7AE58F08D527BB17E4DDBF34A42B919381B3290AD5A4
```
