# Knot-8 v4 Instruction Set Architecture

This document specifies the programmer-visible behavior of Knot-8 v4 as
implemented by `knot8_core.v`. The architecture provides stack-relative
access, two address pointers, read-modify-write memory operations,
carry/borrow propagation, shifts and rotates, and signed branches for C
compilers and small interpreters.

## 1. Core architecture

- Data width: 8 bits
- Address width: 16 bits, byte addressed
- Instruction width: fixed 16 bits
- General-purpose registers: `R0`, `R1`, `R2`, `R3`
- Special registers: 16-bit `PC`, `SP`, `IDX`, `IDY`
- Status register: 8-bit `FLAG`
- Reset vector: `0x0000`
- Initial `SP`: `0xC000`
- Initial `IDX`, `IDY`, `R0`-`R3`, and `FLAG`: zero
- Stack growth: toward lower addresses
- Undefined opcodes: side-effect-free `NOP`
- `HALT`: stops the CPU until reset or a UART loader restart

The CPU has a unified address space. The current board implementation places
4 KiB of program RAM and 16 KiB of data/tape/stack RAM in separate M9K
blocks.

## 2. Byte order and instruction encoding

Instructions are stored most-significant byte first:

```text
memory[PC]     = instruction[15:8]
memory[PC + 1] = instruction[7:0]
```

The instruction formats are:

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

Register numbers are `00=R0`, `01=R1`, `10=R2`, and `11=R3`. For encoding
compatibility, the source register of `PUSH` and `STORE` occupies the `Rs`
field. Other single-register instructions use the `Rd` field.

Instructions are byte-aligned and may begin at either even or odd addresses.
The CPU fetches `PC` and `PC+1` separately, so odd addresses have no
functional or performance penalty. Use assembler directive
`.align power_of_two[, fill_byte]` only when a table or function requires
explicit alignment. `.word` uses the same big-endian order as instructions;
C data objects are little-endian as defined by the ABI.

## 3. Status flags

| Bit | Name | Meaning |
|---:|---|---|
| 0 | `Z` | Result is zero |
| 1 | `C` | Addition carry or subtraction borrow |
| 2 | `N` | Bit 7 of the result |
| 3 | `V` | Two's-complement signed overflow |
| 7:4 | - | Always written as zero |

For `SUB`, `SUBI`, `SBC`, `SBCI`, `CMP`, `CMPI`, `CPC`, and `CPCI`, `C=1`
means that a borrow occurred. Therefore:

```text
SBC  : Rd = Rd - Rs   - C
SBCI : Rd = Rd - imm8 - C
```

The following instructions update `Z/C/N/V`:

- `LOADI`, `MOV`
- All register and immediate forms of `ADD/ADC/SUB/SBC/CMP`
- `CPC`, `CPCI`
- All register and immediate forms of `AND/OR/XOR`
- `SHL`, `SHR`, `SAR`, `ROL`, `ROR`
- `INC_MEM`

Logical operations, `LOADI`, and `MOV` clear `C` and `V`. `CMP` and `CMPI`
update subtraction flags without changing a register. `CPC` and `CPCI` also
preserve their operands and consume the previous borrow. Their zero flag is
sticky:

```text
Z_new = Z_old AND (current_result == 0)
```

A low-byte `CMP`/`CMPI` followed by high-byte `CPC`/`CPCI` operations
therefore leaves `Z` set only when the entire multi-byte value is equal.
Loads, stores, stack operations, pointer operations, and branches preserve
flags, except for `INC_MEM`.

For `SHL` and `ROL`, `V` is the XOR of the old and new bit 7. `SHR`, `SAR`,
and `ROR` clear `V`. The bit shifted out is written to `C`.

## 4. Instructions

In the tables below, `s8` is `-128..127`, `u8` is `0..255`, and `rel8` is a
signed byte offset relative to the instruction following the branch.

### 4.1 Control and stack

| Opcode | Assembly | Operation |
|---:|---|---|
| `00` | `NOP` | Continue with no side effects |
| `01` | `HALT` | Stop the CPU |
| `02` | `SWAPXY` | Exchange `IDX` and `IDY` |
| `03` | `RET` | Pop return address low, then high, and return |
| `04` | `PUSH Rs` | `SP--`, `[SP]=Rs` |
| `05` | `POP Rd` | `Rd=[SP]`, `SP++` |
| `06` | `ADJSP s8` | `SP = SP + sign_extend(s8)` |
| `07` | `LEASP s8` | `IDX = SP + sign_extend(s8)` |
| `0E` | `PUSHI u8` | `SP--`, `[SP]=u8` |

### 4.2 IDX, IDY, and pointer operations

Memory instructions use `IDX` as the active address pointer. `SWAPXY`
exchanges it with auxiliary pointer `IDY` in one instruction. An interpreter
can keep source and tape pointers in the two registers and activate either
one as needed.

| Opcode | Assembly | Operation |
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
| `02` | `SWAPXY` | Exchange `IDX` and `IDY` |

### 4.3 Memory

| Opcode | Assembly | Operation |
|---:|---|---|
| `30` | `LOAD Rd, [IDX]` | `Rd=[IDX]` |
| `31` | `STORE Rs, [IDX]` | `[IDX]=Rs` |
| `0C` | `LOAD_INC Rd` | `Rd=[IDX]`, then `IDX++` |
| `0D` | `STORE_INC Rs` | `[IDX]=Rs`, then `IDX++` |
| `17` | `LOADSP Rd, s8` | `Rd=[SP+sign_extend(s8)]` |
| `18` | `STORESP Rs, s8` | `[SP+sign_extend(s8)]=Rs` |
| `1B` | `LOADX Rd, s8` | `Rd=[IDX+sign_extend(s8)]` |
| `1C` | `STOREX Rs, s8` | `[IDX+sign_extend(s8)]=Rs` |
| `0F` | `INC_MEM` or `INC_MEM [IDX]` | `[IDX]++`, update result flags |

Ordinary loads do not change flags. `INC_MEM` performs a byte
read-modify-write and produces the same flags as addition. `0xFF` wraps to
`0x00` with `C=1`; `0x7F` becomes `0x80` with `V=1`.

`LOAD_INC` and `STORE_INC` support byte-array traversal.
`LOADSP`/`STORESP` access locals and arguments, while `LOADX`/`STOREX`
support structures and pointer-based access.

### 4.4 Immediate ALU

| Opcode | Assembly | Operation |
|---:|---|---|
| `10` | `LOADI Rd, u8` | `Rd=u8` |
| `11` | `ADDI Rd, u8` | `Rd=Rd+u8` |
| `12` | `SUBI Rd, u8` | `Rd=Rd-u8` |
| `13` | `ANDI Rd, u8` | `Rd=Rd AND u8` |
| `14` | `ORI Rd, u8` | `Rd=Rd OR u8` |
| `15` | `XORI Rd, u8` | `Rd=Rd XOR u8` |
| `16` | `CMPI Rd, u8` | Set flags from `Rd-u8` |
| `19` | `ADCI Rd, u8` | `Rd=Rd+u8+C` |
| `1A` | `SBCI Rd, u8` | `Rd=Rd-u8-C` |
| `1E` | `CPCI Rd, u8` | Flags from `Rd-u8-C`; preserve register; sticky `Z` |

The `u8` field is a byte pattern. For convenience, the assembler accepts
values in the range `-128..255`.

### 4.5 Register ALU

| Opcode | Assembly | Operation |
|---:|---|---|
| `20` | `ADD Rd, Rs` | `Rd=Rd+Rs` |
| `21` | `SUB Rd, Rs` | `Rd=Rd-Rs` |
| `22` | `AND Rd, Rs` | `Rd=Rd AND Rs` |
| `23` | `OR Rd, Rs` | `Rd=Rd OR Rs` |
| `24` | `XOR Rd, Rs` | `Rd=Rd XOR Rs` |
| `25` | `CMP Rd, Rs` | Set flags from `Rd-Rs` |
| `26` | `MOV Rd, Rs` | `Rd=Rs` |
| `27` | `ADC Rd, Rs` | `Rd=Rd+Rs+C` |
| `28` | `SBC Rd, Rs` | `Rd=Rd-Rs-C` |
| `2E` | `CPC Rd, Rs` | Flags from `Rd-Rs-C`; preserve registers; sticky `Z` |

For 16-bit addition, use `ADD` on the low byte and `ADC` on the high byte.
For 16-bit subtraction, use `SUB` on the low byte and `SBC` on the high byte.

Multi-byte comparisons must proceed in little-endian order, from the low byte
to the high byte:

```asm
        CMP     a_low,  b_low
        CPC     a_high, b_high
```

A 32-bit comparison appends three `CPC` instructions after the initial
`CMP`. The final `Z` represents full equality, `C` represents unsigned
borrow, and `N XOR V` represents signed less-than. The same comparison chain
therefore supports `==`, `!=`, `<`, `>=`, `>`, and `<=`.

For a 16- or 32-bit zero test, use `CMPI Rd,0` on the low byte and
`CPCI Rd,0` on each remaining byte.

### 4.6 Shifts and rotates

| Opcode | Assembly | Operation |
|---:|---|---|
| `29` | `SHL Rd` | Logical left shift; old bit 7 to `C` |
| `2A` | `SHR Rd` | Logical right shift; old bit 0 to `C` |
| `2B` | `SAR Rd` | Arithmetic right shift; old bit 0 to `C` |
| `2C` | `ROL Rd` | Shift left through carry |
| `2D` | `ROR Rd` | Shift right through carry |

`ROL` and `ROR` rotate through the carry flag and therefore operate on a
9-bit value. For multi-byte shifts, combine `SHL`/`SHR` on the first byte
with `ROL`/`ROR` on subsequent bytes.

### 4.7 Branches and calls

| Opcode | Assembly | Condition or operation |
|---:|---|---|
| `36` | `JUMP` | `PC=IDX` |
| `37` | `CALL` | Push next PC high, then low; set `PC=IDX` |
| `38` | `JUMP_REL rel8` | Unconditional relative branch |
| `39` | `BRZ rel8` | `Z=1` |
| `3A` | `BRNZ rel8` | `Z=0` |
| `3B` | `BRC rel8` | `C=1` |
| `3C` | `BRNC rel8` | `C=0` |
| `3D` | `BRLT rel8` | Signed less-than: `N XOR V` |
| `3E` | `BRGE rel8` | Signed greater-or-equal: `NOT(N XOR V)` |
| `3F` | `BRGT rel8` | Signed greater-than: `NOT Z AND NOT(N XOR V)` |

Relative branches use:

```text
target = PC + 2 + sign_extend(rel8)
```

The range is `-128..+127` bytes from the following instruction. A longer
conditional branch can invert the condition to skip a
`LOADI_H`/`LOADI_L`/`JUMP` sequence.

After `CMP`/`CMPI` or a complete `CPC`/`CPCI` chain, `BRC` means unsigned
less-than and `BRNC` means unsigned greater-or-equal. Unsigned greater-than
is `Z=0 AND C=0`; unsigned less-or-equal is `Z=1 OR C=1`.

## 5. Board memory map

| Address | Size | Function |
|---:|---:|---|
| `0000-0FFF` | 4096 B | Program/data RAM written by the UART loader |
| `8000-BFFF` | 16384 B | Compiler globals/data, TP2B tape, and stack RAM |
| `FF00` | 1 B | LED output/readback, low four bits |
| `FF01` | 1 B | Button input `{6'b0,S4_n,S3_n}` |
| `FF02` | 1 B | UART TX data; write when ready |
| `FF03` | 1 B | UART TX status; bit 0 is ready |
| Other | - | Reads return `00`; writes are ignored |

The CPU may also write program RAM. Both RAMs are byte-addressed. There is no
hardware bounds checking, stack-overflow checking, or execute permission.

FPGA configuration initializes program RAM with the built-in demo. S2 reset
preserves program RAM. In contrast, the hardware scrubber clears the entire
data/tape/stack RAM on reset release and after each UART program upload. The
CPU remains in reset while scrubbing. At 50 MHz, clearing 16,384 bytes takes
16,384 clocks, approximately 0.328 ms. The loader sends its ACK only after
both CRC verification and scrubbing complete.

## 6. Instruction timing in board RAM

The following counts are measured from one instruction start to the next
using the board's 50 MHz, one-cycle synchronous M9K read interface.

| Class | Clocks |
|---|---:|
| ALU, compare, branch, pointer, `NOP` | 6 |
| Store, `PUSH`, `PUSHI` | 8 |
| Load, `POP` | 9 |
| `INC_MEM` | 10 |
| `CALL` | 9 |
| `RET` | 11 |

If a memory implementation asserts `mem_read_valid` later, the CPU waits in
its read state for the additional cycles. `HALT` remains in the execute state
indefinitely.

## 7. Encoding compatibility

- All opcode encodings defined before v4 remain unchanged.
- `programs/counter.asm` assembles byte-for-byte identically.
- Opcodes `02` and `0F` are `SWAPXY` and `INC_MEM`.
- Opcodes `1E` and `2E` are `CPCI` and `CPC`.
- v4 defines data-RAM scrubbing and byte-aligned instruction fetch.
- The UART loader accepts the `K8` packet magic and the earlier `R8` magic.
