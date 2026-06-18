#!/usr/bin/env python3
"""Tests for validate_prd_frontmatter.py — PRD frontmatter validation before fanout."""
from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

LIB = Path(__file__).resolve().parent
sys.path.insert(0, str(LIB))

import validate_prd_frontmatter as vpf  # noqa: E402


VALID_PRD = """\
---
slug: auth-feature
tickets:
  - id: auth-login
    repo: org/web
    capability: auth UI
    title: "Auth: login flow"
    owner: frontend-dev
    acceptance:
      - user can log in
    commit_message: "feat(auth): add login"
---

# Auth feature PRD
"""

MISSING_FIELD_PRD = """\
---
tickets:
  - id: auth-login
    repo: org/web
    capability: auth UI
    title: "Auth: login flow"
---

# Missing owner and acceptance
"""

NO_FRONTMATTER = """\
# Just a regular markdown file
"""

EMPTY_TICKETS = """\
---
slug: empty
tickets: []
---

# No tickets
"""


class ExtractFrontmatterTests(unittest.TestCase):
    def test_valid_frontmatter(self) -> None:
        result = vpf.extract_frontmatter(VALID_PRD)
        self.assertIn("slug: auth-feature", result)

    def test_no_frontmatter_raises(self) -> None:
        with self.assertRaises(ValueError):
            vpf.extract_frontmatter(NO_FRONTMATTER)


class MainIntegrationTests(unittest.TestCase):
    def _run(self, content: str) -> tuple[int, str, str]:
        tmp = tempfile.NamedTemporaryFile(suffix=".md", delete=False, mode="w")
        tmp.write(content)
        path = Path(tmp.name)
        tmp.close()
        proc = subprocess.run(
            [sys.executable, str(LIB / "validate_prd_frontmatter.py"), str(path)],
            capture_output=True,
            text=True,
        )
        path.unlink(missing_ok=True)
        return proc.returncode, proc.stdout, proc.stderr

    def test_valid_prd_passes(self) -> None:
        code, out, err = self._run(VALID_PRD)
        self.assertEqual(code, 0)
        self.assertIn("1 tickets", out)

    def test_missing_fields_fails(self) -> None:
        code, out, err = self._run(MISSING_FIELD_PRD)
        self.assertNotEqual(code, 0)
        self.assertIn("missing owner", err)
        self.assertIn("missing acceptance", err)

    def test_no_frontmatter_fails(self) -> None:
        code, out, err = self._run(NO_FRONTMATTER)
        self.assertNotEqual(code, 0)

    def test_empty_tickets_fails(self) -> None:
        code, out, err = self._run(EMPTY_TICKETS)
        self.assertNotEqual(code, 0)
        self.assertIn("non-empty", err)

    def test_missing_file_fails(self) -> None:
        proc = subprocess.run(
            [sys.executable, str(LIB / "validate_prd_frontmatter.py"), "/nonexistent.md"],
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(proc.returncode, 0)

    def test_commit_message_with_colon_unquoted_causes_yaml_error(self) -> None:
        prd = """\
---
tickets:
  - id: t1
    repo: org/web
    capability: auth
    title: Login
    owner: dev
    acceptance:
      - works
    commit_message: feat(auth): login
---
"""
        code, out, err = self._run(prd)
        self.assertNotEqual(code, 0)
        self.assertIn("YAML", err)


if __name__ == "__main__":
    unittest.main()
