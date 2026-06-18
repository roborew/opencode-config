#!/usr/bin/env python3
"""Tests for extract_issue_sections.py — section extraction, JSON block parsing, placeholder detection."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

LIB = Path(__file__).resolve().parent
sys.path.insert(0, str(LIB))

import extract_issue_sections as eis  # noqa: E402


FULL_BODY = """\
Parent PRD: https://github.com/org/spec/issues/1

```opencode-task-json
{"task_id": "auth-login", "owner": "developer", "stages": [{"stage_id": "s1"}]}
```

## User stories covered

As a user I can log in with email and password.

## Implementation plan

1. Add login endpoint
2. Add JWT token generation
"""

PLACEHOLDER_BODY = """\
## User stories covered

_To be completed by issue-expand` in the implementation repo

## Implementation plan

_To be completed by issue-expand` in the implementation repo
"""


class SectionTests(unittest.TestCase):
    def test_extracts_user_stories(self) -> None:
        result = eis.section(FULL_BODY, "User stories covered")
        self.assertIn("log in with email", result)

    def test_extracts_implementation_plan(self) -> None:
        result = eis.section(FULL_BODY, "Implementation plan")
        self.assertIn("login endpoint", result)

    def test_missing_section_returns_none(self) -> None:
        self.assertIsNone(eis.section(FULL_BODY, "Nonexistent"))


class ExtractJsonBlockTests(unittest.TestCase):
    def test_parses_valid_json_block(self) -> None:
        result = eis.extract_json_block(FULL_BODY)
        self.assertIsNotNone(result)
        self.assertEqual(result["task_id"], "auth-login")
        self.assertEqual(result["owner"], "developer")

    def test_missing_block_returns_none(self) -> None:
        self.assertIsNone(eis.extract_json_block("no fence here"))

    def test_invalid_json_returns_none(self) -> None:
        body = "```opencode-task-json\n{invalid json}\n```"
        self.assertIsNone(eis.extract_json_block(body))


class IsPlaceholderTests(unittest.TestCase):
    def test_none_is_placeholder(self) -> None:
        self.assertTrue(eis.is_placeholder(None))

    def test_empty_is_placeholder(self) -> None:
        self.assertTrue(eis.is_placeholder(""))

    def test_issue_expand_placeholder(self) -> None:
        self.assertTrue(eis.is_placeholder("_To be completed by issue-expand here"))

    def test_real_content_not_placeholder(self) -> None:
        self.assertFalse(eis.is_placeholder("Add the auth login endpoint"))

    def test_non_underscore_start_not_placeholder(self) -> None:
        self.assertFalse(eis.is_placeholder("Some normal content"))


class MainOutputTests(unittest.TestCase):
    def test_full_body_preserves_sections(self) -> None:
        import json
        import io
        old_stdin, old_stdout = sys.stdin, sys.stdout
        sys.stdin = io.StringIO(FULL_BODY)
        sys.stdout = io.StringIO()
        eis.main()
        sys.stdout.seek(0)
        result = json.loads(sys.stdout.read())
        sys.stdin, sys.stdout = old_stdin, old_stdout

        self.assertTrue(result["preserve_user_stories"])
        self.assertTrue(result["preserve_implementation_plan"])
        self.assertEqual(result["meta"]["task_id"], "auth-login")
        self.assertTrue(result["preserve_stages"])

    def test_placeholder_body_does_not_preserve(self) -> None:
        import json
        import io
        old_stdin, old_stdout = sys.stdin, sys.stdout
        sys.stdin = io.StringIO(PLACEHOLDER_BODY)
        sys.stdout = io.StringIO()
        eis.main()
        sys.stdout.seek(0)
        result = json.loads(sys.stdout.read())
        sys.stdin, sys.stdout = old_stdin, old_stdout

        self.assertFalse(result["preserve_user_stories"])
        self.assertFalse(result["preserve_implementation_plan"])


if __name__ == "__main__":
    unittest.main()
