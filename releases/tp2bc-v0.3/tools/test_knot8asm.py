#!/usr/bin/env python3
"""Regression tests for the Knot-8 v4 assembler."""

from __future__ import annotations

import pathlib
import tempfile
import unittest

from knot8asm import AssemblyError, assemble


def assemble_text(source: str) -> tuple[bytes, list[str]]:
    with tempfile.TemporaryDirectory() as directory:
        path = pathlib.Path(directory) / "test.asm"
        path.write_text(source, encoding="utf-8")
        return assemble(path)


class Knot8AssemblerTests(unittest.TestCase):
    def test_v4_compare_encodings(self) -> None:
        image, _ = assemble_text("CPCI R1, 0\nCPC R2, R3\n")
        self.assertEqual(image, bytes((0x79, 0x00, 0xBA, 0xC0)))

    def test_byte_aligned_instruction_and_explicit_alignment(self) -> None:
        image, listing = assemble_text(
            ".byte 0xAA\n"
            "odd: NOP\n"
            ".align 4, 0xFF\n"
            "aligned: HALT\n"
        )
        self.assertEqual(image, bytes((0xAA, 0x00, 0x00, 0xFF, 0x04, 0x00)))
        self.assertTrue(any(line.startswith("0001") and "NOP" in line for line in listing))
        self.assertTrue(any(line.startswith("0004") and "HALT" in line for line in listing))

    def test_relative_branch_across_alignment_padding(self) -> None:
        image, _ = assemble_text(
            "JUMP_REL target\n"
            ".byte 0xAA\n"
            ".align 2\n"
            "target: HALT\n"
        )
        self.assertEqual(image[:2], bytes((0xE0, 0x02)))
        self.assertEqual(image[2:], bytes((0xAA, 0x00, 0x04, 0x00)))

    def test_alignment_requires_power_of_two(self) -> None:
        with self.assertRaisesRegex(AssemblyError, "power of two"):
            assemble_text(".align 3\nNOP\n")


if __name__ == "__main__":
    unittest.main()
