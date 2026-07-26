# tp2b compiler for Knot-8

`tools/tp2bc.py`는 별도 원본 `tp2b.asm`으로 검증한 의미론을 Knot-8
v4로 옮기는 compiler다. 실행과 시험에 필요한 예제는 이 폴더에
포함되어 있으며 원본 checkout은 필요하지 않다.

## Packed backend (default)

기본 `--backend packed`는 tp2b 전체를 FPGA에서 실제 실행한다.

- `(`, `L`, EOF, BOF를 각각 하나의 2-bit token으로 저장
- Knot-8 interpreter가 4-state FSM과 forward/backward loop scan 실행
- cell test, pointer 이동, 8-bit wrap과 output은 모두 FPGA에서 실행
- target tape는 reset 때 0이 되는 `0x8000-0xBFF7` 16,376 cells
- `0xBFF8-0xBFFF` 8 bytes는 interpreter 변수로 예약
- UART output은 Knot-8 `FF02/FF03` MMIO 사용

```powershell
python .\tools\tp2bc.py .\tp2b\examples\hello_worlda.tp `
  -o .\build\tp2b\hello_worlda_packed.bin `
  -S .\build\tp2b\hello_worlda_packed.asm `
  -l .\build\tp2b\hello_worlda_packed.lst

.\upload_program.ps1 .\build\tp2b\hello_worlda_packed.bin `
  -Port COM6 -CaptureOutput
```

가장 큰 원본 예제인 `hello_worlda.tp`도 2,691 bytes로 4KiB program
RAM에 들어간다. 실제 DEV190806037 FPGA에서 packed interpreter,
FSM과 tape를 실행해 `Hello, World!`를 출력했다.

BOF와 EOF가 token stream 안에 있으므로 짝이 없는 loop를 실행 중
만났을 때 조용히 종료하는 원본 동작도 FPGA에서 재현한다.

| source | commands | packed image | FPGA result |
|---|---:|---:|---|
| `exclamation.tp` | 165 | 770 B | `!` |
| `hello_world.tp` | 3,892 | 1,702 B | `Sibal\n` |
| `hello_worlda.tp` | 7,847 | 2,691 B | `Hello, World!` |

## Native backend

`--backend native`는 source position과 FSM state의 product CFG를
Knot-8 code로 직접 펼친다. 예를 들어 `L` in `S1`은 실제
`INC_MEM [IDX]`가 되고, cell test도 FPGA 실행 중 결정된다.

165-command `exclamation.tp`는 1,138 bytes이고 실제 FPGA에서 `!`를
출력했다. packed보다 작은 interpreter overhead 없이 빠르지만 큰
source는 4KiB를 넘으므로 작은 program 또는 backend 비교에 적합하다.

## Const backend

`--backend const`는 input 없는 현재 tp2b의 결정성을 이용하는
whole-program optimization mode다. 원본 30,000-cell tape를 compile
time에 평가하고 최종 output loop만 만든다.

```powershell
python .\tools\tp2bc.py .\tp2b\examples\hello_worlda.tp `
  --backend const `
  -o .\build\tp2b\hello_worlda_const.bin `
  -S .\build\tp2b\hello_worlda_const.asm `
  --print-output
```

| source | compile-time output | const image |
|---|---|---:|
| `exclamation.tp` | `!` | 47 B |
| `hello_world.tp` | `Sibal\n` | 52 B |
| `hello_worlda.tp` | `Hello, World!` | 59 B |

세 output은 WSL에서 원본 x86-64 executable을 실행한 결과와
byte-for-byte 비교했다. Const backend는 최적화/검증에는 유용하지만
tp2b 실행 과정 자체를 FPGA에 보존하지는 않는다.

## 공통 제한

- packed backend의 tape 크기는 16,376 cells, native backend는 16,384
  cells이며 둘 다 원본의 30,000 cells와 다르다.
- const backend 기본 실행 한도는 10,000,000 commands다.
- 원본 interpreter가 unmatched runtime loop scan에서 조용히 종료하는
  동작도 보존한다.
- input 또는 외부 상태가 언어에 추가되면 packed/native backend를
  사용해야 한다.
