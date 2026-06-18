#!/usr/bin/env python3
"""Tests for prd_io.py — PRD frontmatter extraction and loading."""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

LIB = Path(__file__).resolve().parent
sys.path.insert(0, str(LIB))

import prd_io  # noqa: E402


VALID_PRD = """\
---
slug: auth-feature
tickets:
  - id: auth-login
    repo: org/web
    title: "Auth: login"
  - id: auth-signup
    repo: org/web
    title: "Auth: signup"
slices:
  mvp:
    - auth-login
  v2:
    - auth-signup
---

# Auth Feature
"""

NO_FRONTMATTER = "# Just a markdown file\n"


class ExtractFrontmatterTests(unittest.TestCase):
    def test_valid_extraction(self) -> None:
        fm = prd_io.extract_frontmatter(VALID_PRD)
        self.assertIn("slug: auth-feature", fm)

    def test_no_delimiter_raises(self) -> None:
        with self.assertRaises(ValueError):
            prd_io.extract_frontmatter(NO_FRONTMATTER)

    def test_single_delimiter_raises(self) -> None:
        with self.assertRaises(ValueError):
            prd_io.extract_frontmatter("---\nno closing delimiter")


class LoadPrdTests(unittest.TestCase):
    def _write(self, content: str) -> Path:
        f = tempfile.NamedTemporaryFile(suffix=".md", delete=False, mode="w")
        f.write(content)
        f.close()
        return Path(f.name)

    def test_loads_valid_prd(self) -> None:
        p = self._write(VALID_PRD)
        data = prd_io.load_prd(p)
        self.assertEqual(data["slug"], "auth-feature")
        self.assertEqual(len(data["tickets"]), 2)
        p.unlink(missing_ok=True)

    def test_non_dict_frontmatter_raises(self) -> None:
        p = self._write("---\n- just a list\n---\n")
        with self.assertRaises(ValueError):
            prd_io.load_prd(p)
        p.unlink(missing_ok=True)


class MainCliTests(unittest.TestCase):
    def _write(self, content: str) -> Path:
        f = tempfile.NamedTemporaryFile(suffix=".md", delete=False, mode="w")
        f.write(content)
        f.close()
        return Path(f.name)

    def _run(self, *args: str) -> tuple[int, str, str]:
        proc = subprocess.run(
            [sys.executable, str(LIB / "prd_io.py"), *args],
            capture_output=True,
            text=True,
        )
        return proc.returncode, proc.stdout.strip(), proc.stderr.strip()

    def test_tickets_json(self) -> None:
        p = self._write(VALID_PRD)
        code, out, _ = self._run("tickets_json", str(p))
        self.assertEqual(code, 0)
        tickets = json.loads(out)
        self.assertEqual(len(tickets), 2)
        p.unlink(missing_ok=True)

    def test_tickets_count(self) -> None:
        p = self._write(VALID_PRD)
        code, out, _ = self._run("tickets_count", str(p))
        self.assertEqual(code, 0)
        self.assertEqual(out, "2")
        p.unlink(missing_ok=True)

    def test_slices_json(self) -> None:
        p = self._write(VALID_PRD)
        code, out, _ = self._run("slices_json", str(p))
        self.assertEqual(code, 0)
        slices = json.loads(out)
        self.assertIn("mvp", slices)
        p.unlink(missing_ok=True)

    def test_get_field(self) -> None:
        p = self._write(VALID_PRD)
        code, out, _ = self._run("get", str(p), "slug")
        self.assertEqual(code, 0)
        self.assertEqual(out, "auth-feature")
        p.unlink(missing_ok=True)

    def test_missing_file(self) -> None:
        code, _, err = self._run("tickets_json", "/nonexistent.md")
        self.assertNotEqual(code, 0)

    def test_unknown_command(self) -> None:
        p = self._write(VALID_PRD)
        code, _, err = self._run("bad_command", str(p))
        self.assertNotEqual(code, 0)
        p.unlink(missing_ok=True)


if __name__ == "__main__":
    unittest.main()
