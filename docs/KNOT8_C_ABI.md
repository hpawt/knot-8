# Knot-8 v4 C ABI

이 문서는 앞으로 만들 C 컴파일러, assembler, linker, runtime이 함께
따를 application binary interface다. 현재 RTL과
`programs/c_abi_demo.asm`은 이 규약의 stack frame과 return value를
검증한다.

## 1. C 데이터 모델

Knot-8은 byte-addressed 8비트 CPU이며 다음 데이터 모델을 사용한다.

| C 형식 | 크기 | 정렬 |
|---|---:|---:|
| `_Bool`, `char`, `signed char`, `unsigned char` | 1 B | 1 |
| `short`, `unsigned short` | 2 B | 1 |
| `int`, `unsigned int` | 2 B | 1 |
| `long`, `unsigned long` | 4 B | 1 |
| `long long`, `unsigned long long` | 8 B | 1 |
| object/function pointer | 2 B | 1 |
| `float` | 4 B | 1 |
| `double`, `long double` | 4 B | 1 |

- `CHAR_BIT=8`
- plain `char`는 signed
- `size_t`는 `unsigned int`
- `ptrdiff_t`는 `int`
- 모든 data object는 little-endian
- 모든 object alignment는 1 byte

초기 컴파일러에서 64비트 정수와 부동소수점은 runtime helper 호출로
구현하거나 명시적으로 미지원 처리할 수 있다. 이 경우에도 object
layout은 위 표를 유지해야 나중의 ABI가 깨지지 않는다.

## 2. 레지스터 사용

| 자원 | ABI 용도 |
|---|---|
| `R0` | 8비트 return, 16/32비트 return의 최하위 byte |
| `R1` | 16비트 return의 상위 byte |
| `R2`, `R3` | 32비트 return의 상위 byte |
| `IDX` | 활성 address pointer, indirect call/jump |
| `IDY` | `SWAPXY`로 보존하는 두 번째 address pointer |
| `SP` | hardware stack pointer |
| `FLAG` | 조건 코드 |

`R0`-`R3`, `IDX`, `IDY`, `FLAG`는 모두 caller-saved다. 함수 호출 뒤에도
필요한 값은 caller가 stack/local에 저장한다. `SP`만 callee가 함수
진입 전 값으로 복원한 뒤 `RET`해야 한다.

이 선택은 레지스터가 네 개뿐인 CPU에서 callee-save prologue를 피하고
compiler register allocator를 단순하게 만든다.

## 3. 값 반환

| 반환값 | 위치 |
|---|---|
| `void` | 없음 |
| 1 B scalar | `R0` |
| 2 B scalar/pointer | `R1:R0`, `R0`가 low byte |
| 4 B scalar | `R3:R2:R1:R0`, `R0`가 low byte |

4바이트보다 큰 scalar와 모든 structure/union은 caller가 마련한 result
buffer의 16비트 pointer를 숨은 첫 번째 인수로 전달한다. callee는 그
buffer에 결과를 기록한다. 초기 compiler는 작은 structure도 같은
방식으로 처리하여 규칙을 하나로 유지한다.

## 4. 인수 전달

모든 인수는 stack으로 전달한다.

1. C의 default argument promotion과 prototype 변환을 적용한다.
2. 인수를 오른쪽에서 왼쪽 순서로 push한다.
3. 각 다중 byte 인수는 high byte부터 low byte 순서로 push한다.
4. caller가 `CALL` 뒤에 `ADJSP`로 인수 영역을 제거한다.

그러면 메모리에서는 각 값이 little-endian이고 첫 번째 인수가 가장
낮은 주소에 놓인다. 예를 들어 `f(uint16_t a, uint16_t b)` 진입 시:

```text
높은 주소
SP+7  b high
SP+6  b low
SP+5  a high
SP+4  a low
SP+3  return high
SP+2  return low
SP+1  local 1       <- 2-byte local frame을 만든 뒤
SP+0  local 0       <- 현재 SP
낮은 주소
```

frame을 만들기 전 함수 진입 직후에는:

```text
[SP+0] return low
[SP+1] return high
[SP+2] first argument byte 0
[SP+3] first argument byte 1
...
```

`CALL`은 return address를 high byte, low byte 순서로 push하므로 최종
`SP`가 return low byte를 가리킨다.

## 5. 함수 prologue와 epilogue

크기가 `N`인 local frame의 기본형은 다음과 같다.

```asm
function:
        ADJSP   -N
        ; local byte i:       LOADSP/STORESP ..., i
        ; return low byte:    [SP + N]
        ; return high byte:   [SP + N + 1]
        ; first argument:     [SP + N + 2]
        ...
        ADJSP   N
        RET
```

`ADJSP`, `LOADSP`, `STORESP`의 offset은 signed 8비트다. frame이나
argument offset이 이 범위를 넘으면 compiler는:

- `ADJSP`를 여러 번 내보내고
- `LEASP` 또는 `LEASP 0`으로 `IDX`를 만든 뒤
- `ADJIDX`, `LOADX`, `STOREX`를 사용한다.

stack과 명령어는 모두 byte-aligned이므로 padding은 필요 없다.
함수도 홀수 주소에서 시작할 수 있다. linker가 table 또는 외부
interface 때문에 정렬해야 할 때만 assembler의 `.align`을 사용한다.

## 6. 호출 예

다음은 `uint16_t add_one(uint16_t value)`를 호출하는 실제 Knot-8
코드의
핵심이다.

```asm
        PUSHI   0x00             ; value high
        PUSHI   0x0A             ; value low
        LOADI_H HIGH(add_one)
        LOADI_L LOW(add_one)
        CALL
        ADJSP   2                ; caller cleanup
        ; R1:R0 = 0x000B

add_one:
        ADJSP   -2               ; local frame
        LOADSP  R0, 4            ; argument low
        LOADSP  R1, 5            ; argument high
        ADDI    R0, 1
        ADCI    R1, 0
        STORESP R0, 0
        STORESP R1, 1
        LOADSP  R0, 0
        LOADSP  R1, 1
        ADJSP   2
        RET
```

전체 코드는 `programs/c_abi_demo.asm`에 있다.

## 7. 전역 메모리와 stack

현재 board memory layout은 다음 방향으로 사용한다.

```text
8000  globals, static data, BSS  ───────►
                                      free
BFFF  ◄──────────────────────────── stack
C000  initial empty SP
```

- linker는 `.data`와 `.bss`를 `0x8000`부터 위로 배치한다.
- reset 직후 `SP=0xC000`이며 첫 push는 `0xBFFF`를 사용한다.
- stack은 `0xBFFF`에서 낮은 주소 방향으로 성장한다.
- program RAM `0x0000-0x0FFF`에는 `.text`, read-only constant, loader
  image가 들어간다.
- hardware stack overflow 검사는 없으므로 linker/runtime가 data-stack
  충돌을 막아야 한다.
- reset release와 UART program upload 때 hardware scrubber가 data RAM
  전 영역을 0으로 만든 뒤 CPU를 시작한다.
- C startup code는 initialized `.data`를 program image에서 data RAM으로
  복사해야 한다. `.bss`는 hardware가 이미 0으로 만들지만 runtime도
  ABI 이식성을 위해 필요한 범위만 다시 0으로 지울 수 있다.

현재 UART loader는 `0x0000-0x0FFF`만 기록한다. 따라서 initialized
global의 초기 byte는 program image 안에 보관하고 startup code가
data RAM으로 복사한다.

## 8. 비교와 branch lowering

8비트 비교는 `CMP`/`CMPI` 직후 다음 조건을 사용한다.

| C 조건 | unsigned | signed |
|---|---|---|
| `==` | `BRZ` | `BRZ` |
| `!=` | `BRNZ` | `BRNZ` |
| `<` | `BRC` | `BRLT` |
| `>=` | `BRNC` | `BRGE` |
| `>` | `BRZ`로 제외 후 `BRNC` | `BRGT` |
| `<=` | `BRC` 또는 `BRZ` | `BRGT`의 반대 |

16비트 이상 비교는 low byte에 `CMP`/`CMPI`, 이어지는 높은 byte에
`CPC`/`CPCI`를 사용한다. 이 명령들은 operand register를 보존한다.

```asm
        ; R1:R0과 R3:R2의 16비트 비교
        CMP     R0, R2
        CPC     R1, R3
```

`CPC/CPCI`는 이전 borrow를 입력으로 받고 `Z_new = Z_old AND
(byte_result == 0)`으로 equality를 누적한다. 마지막 플래그의 의미는:

| 전체 다중 byte 조건 | lowering |
|---|---|
| `==` / `!=` | `BRZ` / `BRNZ` |
| unsigned `<` / `>=` | `BRC` / `BRNC` |
| signed `<` / `>=` | `BRLT` / `BRGE` |
| signed `>` | `BRGT` |
| unsigned `>` | `BRZ`로 equality 제외 후 `BRNC` |
| unsigned `<=` | `BRC` 또는 `BRZ` |

16/32비트 zero test도 같은 방식으로 low byte에 `CMPI Rn,0`, 나머지
byte에 `CPCI Rn,0`을 적용한다. 마지막 byte만 `CMP`하는 lowering이나
일반 `SBC` chain의 마지막 `Z`만 사용하는 lowering은 금지한다.

## 9. 연산 lowering

- 16비트 add: low `ADD/ADDI`, high `ADC/ADCI`
- 16비트 subtract: low `SUB/SUBI`, high `SBC/SBCI`
- left shift: low byte부터 `SHL`, 이어지는 byte에 `ROL`
- logical right shift: high byte부터 `SHR`, 이어지는 byte에 `ROR`
- arithmetic right shift: 최상위 byte에 `SAR`, 이어지는 byte에 `ROR`
- multiply/divide/modulo: compiler runtime helper
- indirect load/store: pointer를 `SETIDX_H/L`로 옮기고 `LOADX/STOREX`
- direct function call: `LOADI_H HIGH(symbol)`, `LOADI_L LOW(symbol)`, `CALL`
- function pointer call: pointer를 `SETIDX_H/L`로 옮기고 `CALL`

## 10. Variadic 함수와 interrupt

Variadic 인수도 같은 stack layout을 사용하며 default argument
promotion이 필수다. 따라서 `va_list`는 다음 인수 byte를 가리키는
16비트 pointer로 구현할 수 있다.

현재 CPU에는 interrupt가 없다. 추후 interrupt를 추가할 경우 이 문서의
일반 함수 ABI와 별도의 interrupt entry/exit 규약을 정의해야 한다.

## 11. 컴파일러 구현 순서

1. 정수 expression과 local/global load/store
2. `if`, loop, signed/unsigned compare
3. 함수 call, recursion, pointer
4. startup code, `.data`, `.bss`, linker
5. 32비트 정수와 multiply/divide runtime
6. structure, variadic, 선택적 floating-point runtime

이 ABI를 지키면 초기의 단순 compiler와 이후 최적화 compiler가 같은
object/runtime 인터페이스를 공유할 수 있다.
