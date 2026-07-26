#!/usr/bin/env python3
"""Regression tests for the tp2b to Knot-8 compiler."""

from __future__ import annotations

import pathlib
import tempfile
import unittest

from knot8asm import assemble
from tp2bc import (
    _pack_2bit_program,
    compile_source,
    evaluate,
    generate_knot8_assembly,
    generate_native_knot8_assembly,
    generate_packed_knot8_assembly,
    parse_source,
)


PROJECT_ROOT = pathlib.Path(__file__).resolve().parents[1]
EXAMPLES = PROJECT_ROOT / "tp2b" / "examples"


class Tp2bCompilerTests(unittest.TestCase):
    def test_original_examples(self) -> None:
        expected = {
            "exclamation.tp": b"!",
            "hello_world.tp": b"Sibal\n",
            "hello_worlda.tp": b"Hello, World!",
        }
        expected_image_sizes = {
            "exclamation.tp": 47,
            "hello_world.tp": 52,
            "hello_worlda.tp": 59,
        }
        for name, output in expected.items():
            with self.subTest(name=name):
                result, assembly = compile_source(EXAMPLES / name)
                self.assertEqual(result.output, output)
                with tempfile.TemporaryDirectory() as directory:
                    path = pathlib.Path(directory) / "generated.asm"
                    path.write_text(assembly, encoding="utf-8")
                    image, _ = assemble(path)
                self.assertEqual(len(image), expected_image_sizes[name])
                self.assertLessEqual(len(image), 4096)

    def test_non_commands_do_not_change_state(self) -> None:
        commands, pairs = parse_source("abc\n\tL xyz")
        result = evaluate(commands, pairs)
        self.assertEqual(result.steps, 1)
        self.assertEqual(result.final_state, 2)
        self.assertEqual(result.final_pointer, 29_999)

    def test_unmatched_runtime_scan_matches_canonical_exit(self) -> None:
        commands, pairs = parse_source("((")
        result = evaluate(commands, pairs)
        self.assertTrue(result.terminated_by_unmatched_jump)
        self.assertEqual(result.output, b"")

    def test_empty_output_is_a_single_halt(self) -> None:
        commands, pairs = parse_source("")
        result = evaluate(commands, pairs)
        assembly = generate_knot8_assembly(result, "empty.tp")
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "empty.asm"
            path.write_text(assembly, encoding="utf-8")
            image, _ = assemble(path)
        self.assertEqual(image, bytes((0x04, 0x00)))

    def test_native_backend_keeps_fsm_and_tape_live(self) -> None:
        source = (EXAMPLES / "exclamation.tp").read_text(encoding="utf-8")
        commands, pairs = parse_source(source)
        assembly = generate_native_knot8_assembly(
            commands, pairs, "exclamation.tp"
        )
        self.assertIn("FSM state is specialized into control-flow labels", assembly)
        self.assertIn("INC_MEM [IDX]", assembly)
        self.assertNotIn("output_data:", assembly)
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "native.asm"
            path.write_text(assembly, encoding="utf-8")
            image, _ = assemble(path)
        self.assertEqual(len(image), 1138)

    def test_packed_token_format_has_explicit_boundaries(self) -> None:
        commands, _ = parse_source("(L(")
        packed = _pack_2bit_program(commands)
        # Low two bits are first: BOF=3, (=0, L=1, (=0, EOF=2.
        self.assertEqual(packed, bytes((0x13, 0x02)))

    def test_packed_backend_fits_all_original_examples(self) -> None:
        expected_image_sizes = {
            "exclamation.tp": 770,
            "hello_world.tp": 1702,
            "hello_worlda.tp": 2691,
        }
        for name, expected_size in expected_image_sizes.items():
            with self.subTest(name=name):
                source = (EXAMPLES / name).read_text(encoding="utf-8")
                commands, _ = parse_source(source)
                assembly = generate_packed_knot8_assembly(commands, name)
                self.assertIn("FSM, tape, loop scans, and UART output", assembly)
                self.assertIn("INC_MEM [IDX]", assembly)
                self.assertIn("tp_code:", assembly)
                self.assertNotIn("output_data:", assembly)
                with tempfile.TemporaryDirectory() as directory:
                    path = pathlib.Path(directory) / "packed.asm"
                    path.write_text(assembly, encoding="utf-8")
                    image, _ = assemble(path)
                self.assertEqual(len(image), expected_size)
                self.assertLessEqual(len(image), 4096)


if __name__ == "__main__":
    unittest.main()
