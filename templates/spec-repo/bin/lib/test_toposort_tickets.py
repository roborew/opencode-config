#!/usr/bin/env python3
"""Tests for toposort_tickets.py — topological sort of PRD tickets by depends_on."""
from __future__ import annotations

import io
import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

LIB = Path(__file__).resolve().parent
sys.path.insert(0, str(LIB))

import toposort_tickets as ts  # noqa: E402


class ToposortTests(unittest.TestCase):
    def _run_main(self, tickets: list[dict]) -> tuple[int, str, str]:
        stdin_data = json.dumps(tickets)
        with patch("sys.stdin", io.StringIO(stdin_data)), \
             patch("sys.stdout", new_callable=io.StringIO) as mock_out, \
             patch("sys.stderr", new_callable=io.StringIO) as mock_err:
            try:
                ts.main()
                code = 0
            except SystemExit as e:
                code = e.code or 0
        return code, mock_out.getvalue(), mock_err.getvalue()

    def test_no_dependencies(self) -> None:
        tickets = [
            {"id": "a"},
            {"id": "b"},
            {"id": "c"},
        ]
        code, out, _ = self._run_main(tickets)
        self.assertEqual(code, 0)
        ids = out.strip().split("\n")
        self.assertEqual(set(ids), {"a", "b", "c"})

    def test_linear_dependency_chain(self) -> None:
        tickets = [
            {"id": "c", "depends_on": ["b"]},
            {"id": "b", "depends_on": ["a"]},
            {"id": "a"},
        ]
        code, out, _ = self._run_main(tickets)
        self.assertEqual(code, 0)
        ids = out.strip().split("\n")
        self.assertEqual(ids, ["a", "b", "c"])

    def test_diamond_dependency(self) -> None:
        tickets = [
            {"id": "d", "depends_on": ["b", "c"]},
            {"id": "b", "depends_on": ["a"]},
            {"id": "c", "depends_on": ["a"]},
            {"id": "a"},
        ]
        code, out, _ = self._run_main(tickets)
        self.assertEqual(code, 0)
        ids = out.strip().split("\n")
        self.assertLess(ids.index("a"), ids.index("b"))
        self.assertLess(ids.index("a"), ids.index("c"))
        self.assertLess(ids.index("b"), ids.index("d"))
        self.assertLess(ids.index("c"), ids.index("d"))

    def test_cycle_detected(self) -> None:
        tickets = [
            {"id": "a", "depends_on": ["b"]},
            {"id": "b", "depends_on": ["a"]},
        ]
        code, _, err = self._run_main(tickets)
        self.assertEqual(code, 3)
        self.assertIn("cycle", err)

    def test_unknown_dependency_detected(self) -> None:
        tickets = [
            {"id": "a", "depends_on": ["nonexistent"]},
        ]
        code, _, err = self._run_main(tickets)
        self.assertEqual(code, 2)
        self.assertIn("unknown", err)

    def test_non_array_input_rejected(self) -> None:
        code, _, err = self._run_main({"not": "array"})
        self.assertEqual(code, 1)
        self.assertIn("JSON array", err)

    def test_empty_list(self) -> None:
        code, out, _ = self._run_main([])
        self.assertEqual(code, 0)
        self.assertEqual(out.strip(), "")


if __name__ == "__main__":
    unittest.main()
