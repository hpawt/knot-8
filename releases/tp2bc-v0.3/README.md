# tp2bc v0.3

Compact on-FPGA tp2b runtime for Knot-8 v4.

## What runs on the FPGA

- the canonical four-state tp2b FSM
- the live byte tape and wrapping tape pointer
- cell-dependent loop decisions
- forward and backward matching-token scans
- UART output

The source is stored as four 2-bit tokens: `(`, `L`, BOF, and EOF. Explicit
boundary tokens preserve the original interpreter's quiet termination on an
unmatched runtime scan. The runtime reserves eight data-RAM bytes and exposes
a 16,376-cell wrapping tape.

## Verified images

| Source | Commands | Image | Expected output |
|---|---:|---:|---|
| `exclamation.tp` | 165 | 770 B | `!` |
| `hello_world.tp` | 3,892 | 1,702 B | `Sibal\n` |
| `hello_worlda.tp` | 7,847 | 2,691 B | `Hello, World!` |

`hello_worlda_packed.bin` was uploaded to the DEV190806037 board over COM6.
The board acknowledged the 2,691-byte image and returned the 13 output bytes
for `Hello, World!`.

## Usage

`packed` is the default backend:

```powershell
python .\tools\tp2bc.py .\tp2b\examples\hello_worlda.tp `
  -o .\generated\hello_worlda_packed.bin `
  -S .\generated\hello_worlda_packed.asm `
  -l .\generated\hello_worlda_packed.lst
```

The `native` backend remains useful for small, faster programs, while `const`
is an optional compile-time whole-program optimization/reference mode.
