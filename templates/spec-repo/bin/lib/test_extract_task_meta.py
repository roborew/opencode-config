#!/usr/bin/env python3
"""Tests for extract_task_meta.py — parsing opencode-task-yaml and opencode-task-json blocks."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

LIB = Path(__file__).resolve().parent
sys.path.insert(0, str(LIB))

import extract_task_meta as etm  # noqa: E402


JSON_BODY = """\
Some intro text.

```opencode-task-json
{"task_id": "auth-login", "owner": "developer", "commit_message": "feat: login"}
```

More text.
"""

YAML_BODY = """\
Some intro text.

```opencode-task-yaml
task_id: auth-login
owner: developer
commit_message: "feat: login"
```

More text.
"""

EMPTY_BODY = "No fenced code blocks here."

INVALID_JSON_BODY = """\
```opencode-task-json
{this is not valid json
```
"""

EMPTY_FENCE_BODY = """\
```opencode-task-json

```
"""


class ExtractTaskBlockRawTests(unittest.TestCase):
    def test_json_fence(self) -> None:
        result = etm.extract_task_block_raw(JSON_BODY)
        self.assertIsNotNone(result)
        fence, content = result
        self.assertEqual(fence, "opencode-task-json")
        self.assertIn("auth-login", content)

    def test_yaml_fence(self) -> None:
        result = etm.extract_task_block_raw(YAML_BODY)
        self.assertIsNotNone(result)
        fence, content = result
        self.assertEqual(fence, "opencode-task-yaml")
        self.assertIn("auth-login", content)

    def test_no_fence_returns_none(self) -> None:
        self.assertIsNone(etm.extract_task_block_raw(EMPTY_BODY))

    def test_yaml_preferred_over_json_in_iteration(self) -> None:
        body = JSON_BODY + "\n" + YAML_BODY
        result = etm.extract_task_block_raw(body)
        self.assertEqual(result[0], "opencode-task-yaml")


class ParseTaskMetaTests(unittest.TestCase):
    def test_json_meta(self) -> None:
        meta = etm.parse_task_meta(JSON_BODY)
        self.assertIsNotNone(meta)
        self.assertEqual(meta["task_id"], "auth-login")
        self.assertEqual(meta["owner"], "developer")

    def test_yaml_meta(self) -> None:
        meta = etm.parse_task_meta(YAML_BODY)
        self.assertIsNotNone(meta)
        self.assertEqual(meta["task_id"], "auth-login")
        self.assertEqual(meta["owner"], "developer")

    def test_no_block_returns_none(self) -> None:
        self.assertIsNone(etm.parse_task_meta(EMPTY_BODY))

    def test_invalid_json_returns_none(self) -> None:
        self.assertIsNone(etm.parse_task_meta(INVALID_JSON_BODY))

    def test_empty_fence_returns_none(self) -> None:
        self.assertIsNone(etm.parse_task_meta(EMPTY_FENCE_BODY))

    def test_non_dict_json_returns_none(self) -> None:
        body = '```opencode-task-json\n["not", "a", "dict"]\n```'
        self.assertIsNone(etm.parse_task_meta(body))


if __name__ == "__main__":
    unittest.main()
