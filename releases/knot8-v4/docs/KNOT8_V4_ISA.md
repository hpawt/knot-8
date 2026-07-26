# Knot-8 v4 명령어 집합 명세

이 문서는 `knot8_core.v`에 구현된 Knot-8 v4의 프로그래머 관점
명세다. Knot-8은 기존 RISC8 v1/v2와 Knot-8 v3 opcode를 유지하면서 C와
작은 interpreter에 필요한 stack-relative access, 두 포인터,
read-modify-write, carry/borrow, shift/rotate, signed branch를 제공한다.

## 1. 기본 구조

- 데이터 폭: 8비트
- 주소 폭: 16비트, byte addressing
- 명령어 폭: 고정 16비트
- 범용 레지스터: `R0`, `R1`, `R2`, `R3`
- 특수 레지스터: `PC`, `SP`, `IDX`, `IDY` 각 16비트
- 상태 레지스터: `FLAG` 8비트
- 리셋 벡터: `0x0000`
- 리셋 직후 `SP`: `0xC000`
- 리셋 직후 `IDX`, `IDY`, `R0`-`R3`, `FLAG`: 0
- 스택: 낮은 주소 방향으로 성장
- 정의되지 않은 opcode: 부작용 없는 `NOP`
- `HALT`: reset 또는 UART loader가 CPU를 다시 시작할 때까지 정지

CPU 주소 공간은 하나이지만 현재 보드 구현은 4KiB program RAM과
16KiB data/tape/stack RAM을 서로 다른 M9K 블록에 배치한다.

## 2. 바이트 순서와 명령어 인코딩

명령어는 메모리에 high byte 먼저 저장한다.

```text
memory[PC]     = instruction[15:8]
memory[PC + 1] = instruction[7:0]
```

기본 필드는 다음과 같다.

```text
15          10 9       8 7       6 5                   0
+--------------+---------+---------+---------------------+
|  opcode (6)  | Rd (2)  | Rs (2)  | reserved (6)        | register
+--------------+---------+---------+---------------------+
|  opcode (6)  | Rd (2)  | immediate / offset (8)        | immediate
+--------------+---------+--------------------------------+
|  opcode (6)  | unused  | signed relative offset (8)    | branch
+--------------+---------+--------------------------------+
```

레지스터 번호는 `00=R0`, `01=R1`, `10=R2`, `11=R3`이다. v1 호환
인코딩 때문에 `PUSH`와 `STORE`의 source register는 `Rs` 필드에
들어간다. 나머지 한 레지스터 명령은 `Rd` 필드를 사용한다.

명령어는 byte-aligned이며 짝수/홀수 어느 주소에서도 시작할 수 있다.
CPU가 `PC`와 `PC+1`을 각각 fetch하므로 홀수 주소에 성능 또는 기능상
불이익이 없다. assembler의 `.align power_of_two[, fill_byte]`는
table이나 함수에 명시적 정렬이 필요할 때만 사용한다. `.word`는
명령어와 같은 big-endian 순서를 사용하지만 C 데이터 객체는 ABI에
따라 little-endian이다.

## 3. 상태 플래그

| 비트 | 이름 | 의미 |
|---:|---|---|
| 0 | `Z` | 결과가 0 |
| 1 | `C` | 덧셈 carry 또는 뺄셈 borrow |
| 2 | `N` | 결과의 bit 7 |
| 3 | `V` | 2의 보수 signed overflow |
| 7:4 | - | 항상 0으로 기록 |

`SUB`, `SUBI`, `SBC`, `SBCI`, `CMP`, `CMPI`, `CPC`, `CPCI`에서
`C=1`은 borrow가 발생했다는 뜻이다. 따라서 `SBC`는
`Rd = Rd - Rs - C`이고 `SBCI`는 `Rd = Rd - imm8 - C`이다.

다음 명령이 `Z/C/N/V`를 갱신한다.

- `LOADI`, `MOV`
- 모든 `ADD/ADC/SUB/SBC/CMP` register 및 immediate 형식
- `CPC`, `CPCI`
- `AND/OR/XOR` register 및 immediate 형식
- `SHL`, `SHR`, `SAR`, `ROL`, `ROR`
- `INC_MEM`

논리 연산, `LOADI`, `MOV`는 `C=0`, `V=0`으로 만든다. `CMP`와
`CMPI`는 뺄셈 플래그만 만들고 레지스터는 바꾸지 않는다. `CPC`와
`CPCI`도 레지스터를 바꾸지 않으며 이전 borrow를 입력으로 사용한다.
이 두 명령의 `Z`는 `old_Z AND (current_result == 0)`인 sticky 값이다.
따라서 low byte의 `CMP/CMPI` 뒤에 high byte의 `CPC/CPCI`를 연결하면
마지막 `Z`는 전체 다중 byte 값의 equality를 나타낸다. `INC_MEM`을
제외한 load/store, stack, pointer, branch 명령은 플래그를 보존한다.

`SHL`과 `ROL`의 `V`는 이전 bit 7과 새 bit 7의 XOR이다. `SHR`,
`SAR`, `ROR`는 `V=0`으로 만든다. shift/rotate의 `C`에는 밖으로
밀려난 비트가 들어간다.

## 4. 명령어

표에서 `s8`은 `-128..127`, `u8`은 `0..255`, `rel8`은 다음 명령어를
기준으로 한 signed byte offset이다.

### 4.1 제어 및 스택

| Opcode | 어셈블리 | 동작 |
|---:|---|---|
| `00` | `NOP` | 부작용 없이 다음 명령 |
| `01` | `HALT` | CPU 정지 |
| `02` | `SWAPXY` | `IDX`와 `IDY`를 교환 |
| `03` | `RET` | stack에서 return address low, high를 읽어 복귀 |
| `04` | `PUSH Rs` | `SP--`, `[SP]=Rs` |
| `05` | `POP Rd` | `Rd=[SP]`, `SP++` |
| `06` | `ADJSP s8` | `SP = SP + sign_extend(s8)` |
| `07` | `LEASP s8` | `IDX = SP + sign_extend(s8)` |
| `0E` | `PUSHI u8` | `SP--`, `[SP]=u8` |

### 4.2 IDX, IDY와 포인터

일반 memory 명령은 활성 pointer인 `IDX`를 사용한다. `SWAPXY`는
`IDX`와 보조 pointer `IDY`를 한 명령으로 교환한다. 예를 들어
interpreter는 source pointer와 tape pointer를 각각 보존하면서 필요한
쪽만 활성화할 수 있다.

| Opcode | 어셈블리 | 동작 |
|---:|---|---|
| `08` | `SETIDX_H Rn` | `IDX[15:8]=Rn` |
| `09` | `SETIDX_L Rn` | `IDX[7:0]=Rn` |
| `0A` | `GETIDX_H Rd` | `Rd=IDX[15:8]` |
| `0B` | `GETIDX_L Rd` | `Rd=IDX[7:0]` |
| `32` | `LOADI_H u8` | `IDX[15:8]=u8` |
| `33` | `LOADI_L u8` | `IDX[7:0]=u8` |
| `34` | `INC_IDX` | `IDX++` |
| `35` | `DEC_IDX` | `IDX--` |
| `1D` | `ADJIDX s8` | `IDX += sign_extend(s8)` |
| `02` | `SWAPXY` | `IDX`와 `IDY` 교환 |

### 4.3 메모리

| Opcode | 어셈블리 | 동작 |
|---:|---|---|
| `30` | `LOAD Rd, [IDX]` | `Rd=[IDX]` |
| `31` | `STORE Rs, [IDX]` | `[IDX]=Rs` |
| `0C` | `LOAD_INC Rd` | `Rd=[IDX]`, 그 뒤 `IDX++` |
| `0D` | `STORE_INC Rs` | `[IDX]=Rs`, 그 뒤 `IDX++` |
| `17` | `LOADSP Rd, s8` | `Rd=[SP+sign_extend(s8)]` |
| `18` | `STORESP Rs, s8` | `[SP+sign_extend(s8)]=Rs` |
| `1B` | `LOADX Rd, s8` | `Rd=[IDX+sign_extend(s8)]` |
| `1C` | `STOREX Rs, s8` | `[IDX+sign_extend(s8)]=Rs` |
| `0F` | `INC_MEM` 또는 `INC_MEM [IDX]` | `[IDX]++`, 결과 플래그 갱신 |

일반 memory load는 플래그를 바꾸지 않는다. `INC_MEM`은 byte를
read-modify-write하고 ADD와 같은 `Z/C/N/V`를 만든다. `0xFF`는
`0x00`으로 wrap하며 `C=1`, `0x7F`는 `0x80`이 되며 `V=1`이다.
`LOAD_INC`와 `STORE_INC`는
byte 배열 순회, `LOADSP/STORESP`는 함수의 local/argument 접근,
`LOADX/STOREX`는 구조체와 포인터 기반 접근을 위한 명령이다.

### 4.4 Immediate ALU

| Opcode | 어셈블리 | 동작 |
|---:|---|---|
| `10` | `LOADI Rd, u8` | `Rd=u8` |
| `11` | `ADDI Rd, u8` | `Rd=Rd+u8` |
| `12` | `SUBI Rd, u8` | `Rd=Rd-u8` |
| `13` | `ANDI Rd, u8` | `Rd=Rd AND u8` |
| `14` | `ORI Rd, u8` | `Rd=Rd OR u8` |
| `15` | `XORI Rd, u8` | `Rd=Rd XOR u8` |
| `16` | `CMPI Rd, u8` | `Rd-u8`의 플래그만 기록 |
| `19` | `ADCI Rd, u8` | `Rd=Rd+u8+C` |
| `1A` | `SBCI Rd, u8` | `Rd=Rd-u8-C` |
| `1E` | `CPCI Rd, u8` | `Rd-u8-C`, register 보존, sticky `Z` |

`u8` 필드는 byte pattern이므로 어셈블러는 편의를 위해
`-128..255`를 허용한다.

### 4.5 Register ALU

| Opcode | 어셈블리 | 동작 |
|---:|---|---|
| `20` | `ADD Rd, Rs` | `Rd=Rd+Rs` |
| `21` | `SUB Rd, Rs` | `Rd=Rd-Rs` |
| `22` | `AND Rd, Rs` | `Rd=Rd AND Rs` |
| `23` | `OR Rd, Rs` | `Rd=Rd OR Rs` |
| `24` | `XOR Rd, Rs` | `Rd=Rd XOR Rs` |
| `25` | `CMP Rd, Rs` | `Rd-Rs`의 플래그만 기록 |
| `26` | `MOV Rd, Rs` | `Rd=Rs` |
| `27` | `ADC Rd, Rs` | `Rd=Rd+Rs+C` |
| `28` | `SBC Rd, Rs` | `Rd=Rd-Rs-C` |
| `2E` | `CPC Rd, Rs` | `Rd-Rs-C`, register 보존, sticky `Z` |

16비트 덧셈은 low byte에 `ADD`, high byte에 `ADC`를 사용한다. 16비트
뺄셈은 low byte에 `SUB`, high byte에 `SBC`를 사용한다.

다중 byte 비교는 반드시 little-endian 순서, 즉 low byte부터 수행한다.

```asm
        CMP     a_low,  b_low
        CPC     a_high, b_high
```

32비트 비교는 `CPC`를 세 번 이어 붙인다. 최종 `Z`는 전체 equality,
`C`는 unsigned borrow, `N XOR V`는 signed less-than을 뜻한다.
따라서 `==`, `!=`, `<`, `>=`, `>`, `<=`가 모두 같은 compare chain의
최종 플래그를 사용한다. 상수 0과의 16/32비트 zero test는 low byte에
`CMPI Rd,0`, 나머지 byte에 `CPCI Rd,0`을 사용한다.

### 4.6 Shift와 rotate

| Opcode | 어셈블리 | 동작 |
|---:|---|---|
| `29` | `SHL Rd` | 논리 왼쪽 shift, bit 7을 `C`로 |
| `2A` | `SHR Rd` | 논리 오른쪽 shift, bit 0을 `C`로 |
| `2B` | `SAR Rd` | 부호 보존 오른쪽 shift, bit 0을 `C`로 |
| `2C` | `ROL Rd` | `C`를 bit 0으로 넣어 왼쪽 rotate |
| `2D` | `ROR Rd` | `C`를 bit 7로 넣어 오른쪽 rotate |

`ROL/ROR`는 carry를 포함한 9비트 rotate다. 여러 byte 값을 shift할 때
첫 byte에 `SHL/SHR`, 이어지는 byte에 `ROL/ROR`를 조합한다.

### 4.7 분기와 호출

| Opcode | 어셈블리 | 조건 또는 동작 |
|---:|---|---|
| `36` | `JUMP` | `PC=IDX` |
| `37` | `CALL` | 다음 PC를 stack에 high, low 순으로 push하고 `PC=IDX` |
| `38` | `JUMP_REL rel8` | 항상 상대 분기 |
| `39` | `BRZ rel8` | `Z=1` |
| `3A` | `BRNZ rel8` | `Z=0` |
| `3B` | `BRC rel8` | `C=1` |
| `3C` | `BRNC rel8` | `C=0` |
| `3D` | `BRLT rel8` | signed less-than: `N XOR V` |
| `3E` | `BRGE rel8` | signed greater-or-equal: `NOT(N XOR V)` |
| `3F` | `BRGT rel8` | signed greater-than: `NOT Z AND NOT(N XOR V)` |

상대 분기의 target은 다음과 같다.

```text
target = PC + 2 + sign_extend(rel8)
```

범위는 다음 명령어에서 `-128..+127` byte다. 더 먼 분기는 반대 조건의
짧은 분기와 `LOADI_H`, `LOADI_L`, `JUMP` 조합으로 만든다.

Unsigned 비교에서는 `CMP/CMPI` 또는 완성된 `CPC/CPCI` chain 뒤의
`BRC`가 unsigned less-than, `BRNC`가 unsigned greater-or-equal이다.
unsigned greater-than은 `Z=0 AND C=0`, unsigned less-or-equal은
`Z=1 OR C=1`로 판단한다.

## 5. 현재 보드 메모리 맵

| 주소 | 크기 | 기능 |
|---:|---:|---|
| `0000-0FFF` | 4096 B | 프로그램/데이터 RAM, UART loader 기록 대상 |
| `8000-BFFF` | 16384 B | compiler global/data, tp2b tape, stack RAM |
| `FF00` | 1 B | LED 출력/읽기, 하위 4비트 |
| `FF01` | 1 B | 버튼 입력 `{6'b0,S4_n,S3_n}` |
| `FF02` | 1 B | UART TX data, ready일 때 write |
| `FF03` | 1 B | UART TX status, bit 0이 ready |
| 나머지 | - | 읽기 `00`, 쓰기 무시 |

프로그램 RAM은 CPU도 쓸 수 있다. 두 RAM 모두 byte 단위이며 hardware
범위 검사, stack overflow 검사, execute 권한 검사는 없다.

FPGA configuration 때 program RAM에는 내장 demo가 기록된다. S2 reset은
program RAM을 보존한다. 반면 data/tape/stack RAM은 reset release와
UART program upload 때 hardware scrubber가 전 영역을 0으로 만든다.
scrub 중 CPU는 reset에 유지된다. 50MHz에서 16,384 byte 초기화에는
16,384 clocks, 약 0.328ms가 걸린다. loader ACK는 scrub과 CRC 검증이
모두 끝난 뒤 전송된다.

## 6. 보드 RAM에서의 명령 사이클

50 MHz 보드의 1-cycle synchronous M9K read interface에서 다음
instruction 시작까지 필요한 클록 수다.

| 종류 | 클록 |
|---|---:|
| ALU, compare, branch, pointer, `NOP` | 6 |
| store, `PUSH`, `PUSHI` | 8 |
| load, `POP` | 9 |
| `INC_MEM` | 10 |
| `CALL` | 9 |
| `RET` | 11 |

메모리 구현이 `mem_read_valid`를 늦게 내면 CPU는 read state에서 그만큼
더 기다린다. `HALT`는 무기한 실행 state에 머문다.

## 7. 이전 버전 호환성

- RISC8 v1/v2와 Knot-8 v3에서 정의된 모든 opcode encoding을 유지한다.
- 기존 `programs/counter.asm`은 v2/v3/v4에서 byte-for-byte 동일하다.
- v3에서 opcode `02`와 `0F`가 각각 `SWAPXY`, `INC_MEM`이 되었다.
- initial `SP`와 board data/stack RAM 영역은 v3에서 변경됐다.
- v4에서 opcode `1E`와 `2E`가 각각 `CPCI`, `CPC`가 되었다.
- v4는 data RAM reset/upload scrub과 byte-aligned instruction을 명시한다.
- UART loader의 새 magic은 `K8`이지만 기존 `R8` packet도 받는다.
