#!/usr/bin/env python3
"""Tests for validate_issue_body.py — body validation at fanout, expand, and orchestrate levels."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

LIB = Path(__file__).resolve().parent
sys.path.insert(0, str(LIB))

import validate_issue_body as vib  # noqa: E402


VALID_EXPAND_BODY = """\
Parent PRD: https://github.com/org/spec/issues/1

```opencode-task-json
{
  "task_id": "auth-login",
  "owner": "developer",
  "commit_message": "feat(auth): add login",
  "acceptance": ["user can log in"],
  "test_commands": ["npm test"],
  "stages": [
    {
      "stage_id": "s1",
      "owner": "developer",
      "objective": "Add login endpoint",
      "acceptance": ["POST /login returns 200"],
      "test_commands": ["npm test"],
      "commit_message": "feat(auth): login endpoint"
    }
  ]
}
```

## User stories covered

As a user I can log in with my email and password.

## Implementation plan

1. Create the login endpoint
2. Add JWT token generation
"""

FANOUT_BODY = """\
Parent PRD: https://github.com/org/spec/issues/1

```opencode-task-json
{
  "task_id": "auth-login",
  "owner": "developer",
  "commit_message": "feat(auth): add login",
  "acceptance": ["user can log in"],
  "test_commands": ["npm test"]
}
```

## User stories covered

_Map PRD user stories

## Implementation plan

_To be completed
"""


class ExtractSectionTests(unittest.TestCase):
    def test_extracts_section(self) -> None:
        result = vib.extract_section(VALID_EXPAND_BODY, "User stories covered")
        self.assertIn("log in", result)

    def test_missing_section_returns_none(self) -> None:
        self.assertIsNone(vib.extract_section("no sections", "Missing"))


class ExtractMetaTests(unittest.TestCase):
    def test_valid_meta(self) -> None:
        meta = vib.extract_meta(VALID_EXPAND_BODY)
        self.assertEqual(meta["task_id"], "auth-login")

    def test_missing_meta(self) -> None:
        self.assertIsNone(vib.extract_meta("no code block"))

    def test_invalid_json_meta(self) -> None:
        body = "```opencode-task-json\n{bad json\n```"
        self.assertIsNone(vib.extract_meta(body))


class IsPlaceholderTests(unittest.TestCase):
    def test_none(self) -> None:
        self.assertTrue(vib.is_placeholder(None))

    def test_empty(self) -> None:
        self.assertTrue(vib.is_placeholder(""))

    def test_whitespace(self) -> None:
        self.assertTrue(vib.is_placeholder("   "))

    def test_marker(self) -> None:
        self.assertTrue(vib.is_placeholder("_Map PRD user stories to tasks"))

    def test_real_content(self) -> None:
        self.assertFalse(vib.is_placeholder("Implement the login flow"))


class ValidateExpandTests(unittest.TestCase):
    def test_valid_expand_body_no_errors(self) -> None:
        errors = vib.validate(VALID_EXPAND_BODY, "expand", "auth-login")
        self.assertEqual(errors, [])

    def test_missing_parent_prd(self) -> None:
        body = VALID_EXPAND_BODY.replace("Parent PRD: https://github.com/org/spec/issues/1", "")
        errors = vib.validate(body, "expand", None)
        self.assertTrue(any("Parent PRD" in e for e in errors))

    def test_missing_meta_block(self) -> None:
        body = "Parent PRD: https://github.com/org/spec/issues/1\n\n## User stories covered\n\nStory.\n"
        errors = vib.validate(body, "expand", None)
        self.assertTrue(any("opencode-task-json" in e for e in errors))

    def test_task_id_mismatch(self) -> None:
        errors = vib.validate(VALID_EXPAND_BODY, "expand", "wrong-id")
        self.assertTrue(any("mismatch" in e for e in errors))

    def test_placeholder_user_stories_flagged(self) -> None:
        body = VALID_EXPAND_BODY.replace(
            "As a user I can log in with my email and password.",
            "_To be completed",
        )
        errors = vib.validate(body, "expand", "auth-login")
        self.assertTrue(any("User stories" in e for e in errors))

    def test_missing_stages_flagged(self) -> None:
        body = VALID_EXPAND_BODY.replace(
            '"stages": [\n    {\n      "stage_id": "s1",\n      "owner": "developer",\n      "objective": "Add login endpoint",\n      "acceptance": ["POST /login returns 200"],\n      "test_commands": ["npm test"],\n      "commit_message": "feat(auth): login endpoint"\n    }\n  ]',
            '"stages": []',
        )
        errors = vib.validate(body, "expand", "auth-login")
        self.assertTrue(any("stages" in e for e in errors))


class ValidateFanoutTests(unittest.TestCase):
    def test_fanout_allows_placeholder_sections(self) -> None:
        errors = vib.validate(FANOUT_BODY, "fanout", "auth-login")
        self.assertEqual(errors, [])

    def test_fanout_requires_sections_present(self) -> None:
        body = "Parent PRD: https://github.com/org/spec/issues/1\n\n```opencode-task-json\n{\"task_id\": \"x\", \"owner\": \"dev\", \"commit_message\": \"fix\", \"acceptance\": [\"ok\"], \"test_commands\": [\"t\"]}\n```\n"
        errors = vib.validate(body, "fanout", "x")
        self.assertTrue(any("User stories covered" in e for e in errors))
        self.assertTrue(any("Implementation plan" in e for e in errors))


class ValidateOrchestrateTests(unittest.TestCase):
    def test_orchestrate_uses_expand_bar(self) -> None:
        errors = vib.validate(VALID_EXPAND_BODY, "expand", "auth-login")
        self.assertEqual(errors, [])


class StageValidationTests(unittest.TestCase):
    def test_missing_stage_fields(self) -> None:
        body = VALID_EXPAND_BODY.replace(
            '"stage_id": "s1",\n      "owner": "developer",\n      "objective": "Add login endpoint",\n      "acceptance": ["POST /login returns 200"],\n      "test_commands": ["npm test"],\n      "commit_message": "feat(auth): login endpoint"',
            '"stage_id": "s1"',
        )
        errors = vib.validate(body, "expand", "auth-login")
        self.assertTrue(any("stages[0] missing" in e for e in errors))


if __name__ == "__main__":
    unittest.main()
