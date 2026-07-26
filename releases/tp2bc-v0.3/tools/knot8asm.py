#!/usr/bin/env python3
"""Two-pass assembler for the Knot-8 CPU used by this Quartus project."""

from __future__ import annotations

import argparse
import pathlib
import re
import sys
from dataclasses import dataclass


OPCODES = {
    "NOP": 0x00,
    "HALT": 0x01,
    "SWAPXY": 0x02,
    "RET": 0x03,
    "PUSH": 0x04,
    "POP": 0x05,
    "ADJSP": 0x06,
    "LEASP": 0x07,
    "SETIDX_H": 0x08,
    "SETIDX_L": 0x09,
    "GETIDX_H": 0x0A,
    "GETIDX_L": 0x0B,
    "LOAD_INC": 0x0C,
    "STORE_INC": 0x0D,
    "PUSHI": 0x0E,
    "INC_MEM": 0x0F,
    "LOADI": 0x10,
    "ADDI": 0x11,
    "SUBI": 0x12,
    "ANDI": 0x13,
    "ORI": 0x14,
    "XORI": 0x15,
    "CMPI": 0x16,
    "LOADSP": 0x17,
    "STORESP": 0x18,
    "ADCI": 0x19,
    "SBCI": 0x1A,
    "LOADX": 0x1B,
    "STOREX": 0x1C,
    "ADJIDX": 0x1D,
    "CPCI": 0x1E,
    "ADD": 0x20,
    "SUB": 0x21,
    "AND": 0x22,
    "OR": 0x23,
    "XOR": 0x24,
    "CMP": 0x25,
    "MOV": 0x26,
    "ADC": 0x27,
    "SBC": 0x28,
    "SHL": 0x29,
    "SHR": 0x2A,
    "SAR": 0x2B,
    "ROL": 0x2C,
    "ROR": 0x2D,
    "CPC": 0x2E,
    "LOAD": 0x30,
    "STORE": 0x31,
    "LOADI_H": 0x32,
    "LOADI_L": 0x33,
    "INC_IDX": 0x34,
    "DEC_IDX": 0x35,
    "JUMP": 0x36,
    "CALL": 0x37,
    "JUMP_REL": 0x38,
    "BRZ": 0x39,
    "BRNZ": 0x3A,
    "BRC": 0x3B,
    "BRNC": 0x3C,
    "BRLT": 0x3D,
    "BRGE": 0x3E,
    "BRGT": 0x3F,
}

NO_OPERAND = {
    "NOP",
    "HALT",
    "SWAPXY",
    "RET",
    "INC_MEM",
    "INC_IDX",
    "DEC_IDX",
    "JUMP",
    "CALL",
}
ONE_REGISTER = {"PUSH", "POP", "LOAD", "STORE"}
UNARY_REGISTER = {
    "SETIDX_H",
    "SETIDX_L",
    "GETIDX_H",
    "GETIDX_L",
    "LOAD_INC",
    "STORE_INC",
    "SHL",
    "SHR",
    "SAR",
    "ROL",
    "ROR",
}
IMMEDIATE = {
    "LOADI",
    "ADDI",
    "SUBI",
    "ANDI",
    "ORI",
    "XORI",
    "CMPI",
    "ADCI",
    "SBCI",
    "CPCI",
}
REGISTER = {
    "ADD",
    "SUB",
    "AND",
    "OR",
    "XOR",
    "CMP",
    "MOV",
    "ADC",
    "SBC",
    "CPC",
}
IDX_IMMEDIATE = {"LOADI_H", "LOADI_L"}
SIGNED_IMMEDIATE = {"ADJSP", "LEASP", "ADJIDX"}
BYTE_IMMEDIATE = {"PUSHI"}
MEMORY_OFFSET = {"LOADSP", "STORESP", "LOADX", "STOREX"}
RELATIVE = {
    "JUMP_REL",
    "BRZ",
    "BRNZ",
    "BRC",
    "BRNC",
    "BRLT",
    "BRGE",
    "BRGT",
}


class AssemblyError(Exception):
    pass


@dataclass
class SourceLine:
    number: int
    text: str
    address: int
    operation: str
    operands: list[str]


def split_operands(text: str) -> list[str]:
    if not text.strip():
        return []
    return [item.strip() for item in text.split(",")]


def normalize_operand(value: str) -> str:
    return value.strip().upper().replace(" ", "")


def parse_number(token: str, symbols: dict[str, int]) -> int:
    key = token.strip().upper()
    for function_name in ("LOW", "LO8"):
        prefix = function_name + "("
        if key.startswith(prefix) and key.endswith(")"):
            return parse_number(key[len(prefix) : -1], symbols) & 0xFF
    for function_name in ("HIGH", "HI8"):
        prefix = function_name + "("
        if key.startswith(prefix) and key.endswith(")"):
            return (parse_number(key[len(prefix) : -1], symbols) >> 8) & 0xFF
    symbol_expression = re.fullmatch(
        r"([A-Z_][A-Z0-9_]*)([+-])(.+)", key
    )
    if symbol_expression and symbol_expression.group(1) in symbols:
        base = symbols[symbol_expression.group(1)]
        adjustment = parse_number(symbol_expression.group(3), symbols)
        return (
            base + adjustment
            if symbol_expression.group(2) == "+"
            else base - adjustment
        )
    if key in symbols:
        return symbols[key]
    if key.startswith("$"):
        return int(key[1:], 16)
    if re.fullmatch(r"[0-9A-F]+H", key):
        return int(key[:-1], 16)
    if re.fullmatch(r"'(.)'", token.strip()):
        return ord(token.strip()[1])
    try:
        return int(token, 0)
    except ValueError as exc:
        raise AssemblyError(f"unknown number or label '{token}'") from exc


def parse_register(token: str) -> int:
    name = normalize_operand(token)
    if name not in {"R0", "R1", "R2", "R3"}:
        raise AssemblyError(f"expected R0..R3, got '{token}'")
    return int(name[1])


def parse_alignment(
    operands: list[str], symbols: dict[str, int]
) -> tuple[int, int]:
    if len(operands) not in {1, 2}:
        raise AssemblyError(".align syntax is .align power_of_two[, fill_byte]")
    boundary = parse_number(operands[0], symbols)
    if (
        boundary < 1
        or boundary > 4096
        or (boundary & (boundary - 1)) != 0
    ):
        raise AssemblyError(".align boundary must be a power of two from 1..4096")
    fill = parse_number(operands[1], symbols) if len(operands) == 2 else 0
    if fill < -128 or fill > 255:
        raise AssemblyError(".align fill byte is outside -128..255")
    return boundary, fill & 0xFF


def instruction_size(
    operation: str,
    operands: list[str],
    address: int,
    symbols: dict[str, int],
) -> int:
    if operation == ".BYTE":
        if not operands:
            raise AssemblyError(".byte needs at least one value")
        return len(operands)
    if operation == ".WORD":
        if not operands:
            raise AssemblyError(".word needs at least one value")
        return 2 * len(operands)
    if operation == ".ALIGN":
        boundary, _ = parse_alignment(operands, symbols)
        return (-address) % boundary
    if operation in OPCODES:
        return 2
    raise AssemblyError(f"unknown instruction '{operation}'")


def read_source(path: pathlib.Path) -> tuple[list[SourceLine], dict[str, int]]:
    statements: list[SourceLine] = []
    symbols: dict[str, int] = {}
    address = 0

    for number, original in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        text = original.split(";", 1)[0].strip()
        if not text:
            continue

        while ":" in text:
            label, remainder = text.split(":", 1)
            label = label.strip().upper()
            if not re.fullmatch(r"[A-Z_][A-Z0-9_]*", label):
                raise AssemblyError(f"line {number}: invalid label '{label}'")
            if label in symbols:
                raise AssemblyError(f"line {number}: duplicate symbol '{label}'")
            symbols[label] = address
            text = remainder.strip()
            if not text:
                break
        if not text:
            continue

        parts = text.split(None, 1)
        operation = parts[0].upper()
        operands = split_operands(parts[1] if len(parts) == 2 else "")

        if operation == ".EQU":
            if len(operands) != 2:
                raise AssemblyError(f"line {number}: .equ NAME, value")
            name = operands[0].upper()
            if name in symbols:
                raise AssemblyError(f"line {number}: duplicate symbol '{name}'")
            symbols[name] = parse_number(operands[1], symbols)
            continue

        try:
            size = instruction_size(operation, operands, address, symbols)
        except AssemblyError as exc:
            raise AssemblyError(f"line {number}: {exc}") from exc
        statements.append(SourceLine(number, original, address, operation, operands))
        address += size
        if address > 4096:
            raise AssemblyError(f"line {number}: program exceeds 4096 bytes")

    return statements, symbols


def encode_instruction(line: SourceLine, symbols: dict[str, int]) -> list[int]:
    op = line.operation
    args = line.operands

    if op == ".BYTE":
        values = [parse_number(item, symbols) for item in args]
        if any(value < -128 or value > 255 for value in values):
            raise AssemblyError(".byte value is outside -128..255")
        return [value & 0xFF for value in values]

    if op == ".WORD":
        result: list[int] = []
        for item in args:
            value = parse_number(item, symbols)
            if value < -32768 or value > 65535:
                raise AssemblyError(".word value is outside -32768..65535")
            result.extend([(value >> 8) & 0xFF, value & 0xFF])
        return result

    if op == ".ALIGN":
        boundary, fill = parse_alignment(args, symbols)
        return [fill] * ((-line.address) % boundary)

    opcode = OPCODES[op]
    word = opcode << 10

    if op in NO_OPERAND:
        if args and not (len(args) == 1 and normalize_operand(args[0]) == "[IDX]"):
            raise AssemblyError(f"{op} takes no operand")

    elif op in ONE_REGISTER:
        if not args:
            raise AssemblyError(f"{op} needs a register")
        register = parse_register(args[0])
        if len(args) > 2 or (
            len(args) == 2 and normalize_operand(args[1]) != "[IDX]"
        ):
            raise AssemblyError(f"{op} syntax is {op} Rn[, [IDX]]")
        if op in {"POP", "LOAD"}:
            word |= register << 8
        else:
            word |= register << 6

    elif op in UNARY_REGISTER:
        if not args:
            raise AssemblyError(f"{op} needs a register")
        if len(args) > 2 or (
            len(args) == 2 and normalize_operand(args[1]) != "[IDX]"
        ):
            raise AssemblyError(f"{op} syntax is {op} Rn")
        word |= parse_register(args[0]) << 8

    elif op in IMMEDIATE:
        if len(args) != 2:
            raise AssemblyError(f"{op} syntax is {op} Rn, imm8")
        register = parse_register(args[0])
        value = parse_number(args[1], symbols)
        if value < -128 or value > 255:
            raise AssemblyError(f"{op} immediate is outside -128..255")
        word |= (register << 8) | (value & 0xFF)

    elif op in REGISTER:
        if len(args) != 2:
            raise AssemblyError(f"{op} syntax is {op} Rd, Rs")
        word |= (parse_register(args[0]) << 8) | (parse_register(args[1]) << 6)

    elif op in MEMORY_OFFSET:
        if len(args) != 2:
            raise AssemblyError(f"{op} syntax is {op} Rn, signed_offset")
        register = parse_register(args[0])
        offset = parse_number(args[1], symbols)
        if offset < -128 or offset > 127:
            raise AssemblyError(f"{op} offset is outside -128..127")
        word |= (register << 8) | (offset & 0xFF)

    elif op in IDX_IMMEDIATE:
        if len(args) != 1:
            raise AssemblyError(f"{op} needs one imm8 operand")
        value = parse_number(args[0], symbols)
        if value < -128 or value > 255:
            raise AssemblyError(f"{op} immediate is outside -128..255")
        word |= value & 0xFF

    elif op in SIGNED_IMMEDIATE:
        if len(args) != 1:
            raise AssemblyError(f"{op} needs one signed imm8 operand")
        value = parse_number(args[0], symbols)
        if value < -128 or value > 127:
            raise AssemblyError(f"{op} immediate is outside -128..127")
        word |= value & 0xFF

    elif op in BYTE_IMMEDIATE:
        if len(args) != 1:
            raise AssemblyError(f"{op} needs one imm8 operand")
        value = parse_number(args[0], symbols)
        if value < -128 or value > 255:
            raise AssemblyError(f"{op} immediate is outside -128..255")
        word |= value & 0xFF

    elif op in RELATIVE:
        if len(args) != 1:
            raise AssemblyError(f"{op} needs one label or signed offset")
        symbol_name = args[0].strip().upper()
        if symbol_name in symbols:
            offset = symbols[symbol_name] - (line.address + 2)
        else:
            # A numeric operand is a raw signed byte offset. Labels are
            # converted from their absolute byte address above.
            offset = parse_number(args[0], symbols)
        if offset < -128 or offset > 127:
            raise AssemblyError(
                f"{op} target is out of range ({offset}; allowed -128..127)"
            )
        word |= offset & 0xFF

    return [(word >> 8) & 0xFF, word & 0xFF]


def assemble(path: pathlib.Path) -> tuple[bytes, list[str]]:
    statements, symbols = read_source(path)
    output = bytearray()
    listing: list[str] = []

    for line in statements:
        try:
            encoded = encode_instruction(line, symbols)
        except AssemblyError as exc:
            raise AssemblyError(f"line {line.number}: {exc}") from exc
        output.extend(encoded)
        shown = encoded[:8]
        hex_bytes = " ".join(f"{byte:02X}" for byte in shown)
        if len(encoded) > len(shown):
            hex_bytes += f" ... ({len(encoded)} bytes)"
        listing.append(f"{line.address:04X}  {hex_bytes:<12}  {line.text.strip()}")

    return bytes(output), listing


def main() -> int:
    parser = argparse.ArgumentParser(description="Assemble Knot-8 v4 source")
    parser.add_argument("source", type=pathlib.Path, help="input .asm file")
    parser.add_argument("-o", "--output", type=pathlib.Path, required=True)
    parser.add_argument("-l", "--listing", type=pathlib.Path)
    args = parser.parse_args()

    try:
        image, listing = assemble(args.source)
        if len(image) == 0:
            raise AssemblyError("program is empty")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(image)
        if args.listing:
            args.listing.parent.mkdir(parents=True, exist_ok=True)
            args.listing.write_text("\n".join(listing) + "\n", encoding="utf-8")
    except (OSError, AssemblyError) as exc:
        print(f"knot8asm: error: {exc}", file=sys.stderr)
        return 1

    print(f"Assembled {len(image)} bytes -> {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
