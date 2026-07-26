# Knot-8 v4 C ABI

This document defines the application binary interface shared by future C
compilers, the assembler, linker, and runtime. The current RTL and
`programs/c_abi_demo.asm` verify the stack-frame and return-value rules.

## 1. C data model

Knot-8 is a byte-addressed 8-bit CPU with the following data model:

| C type | Size | Alignment |
|---|---:|---:|
| `_Bool`, `char`, `signed char`, `unsigned char` | 1 B | 1 |
| `short`, `unsigned short` | 2 B | 1 |
| `int`, `unsigned int` | 2 B | 1 |
| `long`, `unsigned long` | 4 B | 1 |
| `long long`, `unsigned long long` | 8 B | 1 |
| Object or function pointer | 2 B | 1 |
| `float` | 4 B | 1 |
| `double`, `long double` | 4 B | 1 |

- `CHAR_BIT=8`
- Plain `char` is signed
- `size_t` is `unsigned int`
- `ptrdiff_t` is `int`
- All data objects are little-endian
- Every object has one-byte alignment

An initial compiler may implement 64-bit integers and floating-point
operations through runtime helpers, or report them as unsupported. Their
object layout must still follow this table to preserve ABI compatibility.

## 2. Register use

| Resource | ABI role |
|---|---|
| `R0` | 8-bit return value; least-significant byte of 16/32-bit returns |
| `R1` | Second byte of 16/32-bit returns |
| `R2`, `R3` | Third and fourth bytes of 32-bit returns |
| `IDX` | Active address pointer and indirect call/jump target |
| `IDY` | Auxiliary address pointer exchanged through `SWAPXY` |
| `SP` | Hardware stack pointer |
| `FLAG` | Condition codes |

`R0`-`R3`, `IDX`, `IDY`, and `FLAG` are caller-saved. A caller must spill any
value needed after a call to the stack or a local slot. The callee must only
restore `SP` to its entry value before executing `RET`.

This convention avoids callee-save prologues on a CPU with only four general
registers and keeps register allocation simple.

## 3. Return values

| Return type | Location |
|---|---|
| `void` | None |
| 1-byte scalar | `R0` |
| 2-byte scalar or pointer | `R1:R0`, with the low byte in `R0` |
| 4-byte scalar | `R3:R2:R1:R0`, with the low byte in `R0` |

For scalars larger than four bytes and for every structure or union, the
caller passes a 16-bit pointer to a result buffer as a hidden first argument.
The callee writes the result to that buffer. Initial compilers should use the
same rule even for small structures to keep one consistent convention.

## 4. Argument passing

All arguments are passed on the stack.

1. Apply C default argument promotions and prototype conversions.
2. Push arguments from right to left.
3. Push each multi-byte argument from its high byte to its low byte.
4. After `CALL`, the caller removes the argument area with `ADJSP`.

This produces little-endian values in memory and places the first argument at
the lowest argument address. For `f(uint16_t a, uint16_t b)`, after creating
a two-byte local frame:

```text
Higher addresses
SP+7  b high
SP+6  b low
SP+5  a high
SP+4  a low
SP+3  return high
SP+2  return low
SP+1  local 1
SP+0  local 0       <- current SP
Lower addresses
```

Immediately after function entry, before allocating a local frame:

```text
[SP+0] return low
[SP+1] return high
[SP+2] first argument byte 0
[SP+3] first argument byte 1
...
```

`CALL` pushes the return address high byte and then low byte, leaving `SP`
pointing to the return address low byte.

## 5. Function prologue and epilogue

The basic form for a local frame of `N` bytes is:

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

Offsets in `ADJSP`, `LOADSP`, and `STORESP` are signed eight-bit values. When
a frame or argument offset exceeds that range, the compiler must:

- Emit multiple `ADJSP` instructions
- Form an address in `IDX` with `LEASP` or `LEASP 0`
- Use `ADJIDX`, `LOADX`, and `STOREX`

The stack and instructions are byte-aligned, so no padding is required.
Functions may begin at odd addresses. Use the assembler's `.align` directive
only when a table or external interface requires explicit alignment.

## 6. Call example

The following is the core of a call to
`uint16_t add_one(uint16_t value)`:

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

The complete example is in `programs/c_abi_demo.asm`.

## 7. Global memory and stack

The board memory layout grows in the following directions:

```text
8000  globals, static data, BSS  ───────►
                                      free
BFFF  ◄──────────────────────────── stack
C000  initial empty SP
```

- The linker places `.data` and `.bss` upward from `0x8000`.
- Reset initializes `SP=0xC000`; the first push uses `0xBFFF`.
- The stack grows downward from `0xBFFF`.
- Program RAM `0x0000-0x0FFF` contains `.text`, read-only constants, and the
  loader image.
- There is no hardware stack-overflow check. The linker or runtime must
  prevent a collision between data and stack.
- On reset release and after a UART upload, the hardware scrubber clears the
  entire data RAM before starting the CPU.
- C startup code must copy initialized `.data` from the program image into
  data RAM. Hardware has already cleared `.bss`, though a portable runtime may
  clear the required range again.

The UART loader writes only `0x0000-0x0FFF`. Initial values for global
objects must therefore be stored in the program image and copied to data RAM
by startup code.

## 8. Comparison and branch lowering

An 8-bit comparison uses the following branches immediately after
`CMP`/`CMPI`:

| C condition | Unsigned | Signed |
|---|---|---|
| `==` | `BRZ` | `BRZ` |
| `!=` | `BRNZ` | `BRNZ` |
| `<` | `BRC` | `BRLT` |
| `>=` | `BRNC` | `BRGE` |
| `>` | Exclude equality with `BRZ`, then `BRNC` | `BRGT` |
| `<=` | `BRC` or `BRZ` | Inverse of `BRGT` |

For comparisons of 16 bits or more, use `CMP`/`CMPI` on the low byte and
`CPC`/`CPCI` on each successive high byte. These instructions preserve their
operand registers.

```asm
        ; 16-bit comparison of R1:R0 and R3:R2
        CMP     R0, R2
        CPC     R1, R3
```

`CPC` and `CPCI` consume the previous borrow and accumulate equality using:

```text
Z_new = Z_old AND (byte_result == 0)
```

The final flags have the following meaning:

| Full multi-byte condition | Lowering |
|---|---|
| `==` / `!=` | `BRZ` / `BRNZ` |
| Unsigned `<` / `>=` | `BRC` / `BRNC` |
| Signed `<` / `>=` | `BRLT` / `BRGE` |
| Signed `>` | `BRGT` |
| Unsigned `>` | Exclude equality with `BRZ`, then `BRNC` |
| Unsigned `<=` | `BRC` or `BRZ` |

Use the same chain for a 16- or 32-bit zero test: `CMPI Rn,0` on the low byte
and `CPCI Rn,0` on every remaining byte. Lowering only the final byte with
`CMP`, or relying only on the final `Z` from an ordinary `SBC` chain, is
invalid.

## 9. Operation lowering

- 16-bit addition: low `ADD/ADDI`, high `ADC/ADCI`
- 16-bit subtraction: low `SUB/SUBI`, high `SBC/SBCI`
- Left shift: `SHL` from the low byte, then `ROL` on higher bytes
- Logical right shift: `SHR` from the high byte, then `ROR` on lower bytes
- Arithmetic right shift: `SAR` on the highest byte, then `ROR` on lower bytes
- Multiply, divide, and modulo: compiler runtime helpers
- Indirect load/store: move the pointer with `SETIDX_H/L`, then use
  `LOADX/STOREX`
- Direct function call: `LOADI_H HIGH(symbol)`, `LOADI_L LOW(symbol)`, `CALL`
- Function-pointer call: move the pointer with `SETIDX_H/L`, then `CALL`

## 10. Variadic functions and interrupts

Variadic arguments use the same stack layout and require default argument
promotions. A `va_list` can therefore be a 16-bit pointer to the next
argument byte.

The current CPU has no interrupts. Any future interrupt support must define a
separate entry and exit convention from the ordinary function ABI.

## 11. Compiler implementation order

1. Integer expressions and local/global loads and stores
2. `if`, loops, and signed/unsigned comparisons
3. Function calls, recursion, and pointers
4. Startup code, `.data`, `.bss`, and linker
5. 32-bit integers and multiply/divide runtime helpers
6. Structures, variadic functions, and optional floating-point runtime

Following this ABI allows a simple initial compiler and a later optimizing
compiler to share the same object and runtime interfaces.
