#!/usr/bin/env python3
"""Tests for task_meta_to_yaml.py — converting task meta JSON to opencode-task-yaml."""
from __future__ import annotations

import io
import json
import subprocess
import sys
import unittest
from pathlib import Path

LIB = Path(__file__).resolve().parent
sys.path.insert(0, str(LIB))


class TaskMetaToYamlTests(unittest.TestCase):
    def _run(self, meta: dict | list) -> tuple[int, str, str]:
        proc = subprocess.run(
            [sys.executable, str(LIB / "task_meta_to_yaml.py")],
            input=json.dumps(meta),
            capture_output=True,
            text=True,
        )
        return proc.returncode, proc.stdout.strip(), proc.stderr.strip()

    def test_basic_fields(self) -> None:
        meta = {
            "task_id": "auth-login",
            "owner": "developer",
            "capability": "auth UI",
        }
        code, out, _ = self._run(meta)
        self.assertEqual(code, 0)
        self.assertIn("task_id: auth-login", out)
        self.assertIn("owner: developer", out)
        self.assertIn("capability: auth UI", out)

    def test_depends_on_defaults_to_empty(self) -> None:
        meta = {"task_id": "t1", "owner": "dev"}
        code, out, _ = self._run(meta)
        self.assertEqual(code, 0)
        self.assertIn("depends_on: []", out)

    def test_depends_on_preserved(self) -> None:
        meta = {"task_id": "t1", "owner": "dev", "depends_on": ["t0"]}
        code, out, _ = self._run(meta)
        self.assertEqual(code, 0)
        self.assertIn("t0", out)

    def test_extra_fields_filtered(self) -> None:
        meta = {
            "task_id": "t1",
            "owner": "dev",
            "commit_message": "feat: something",
            "acceptance": ["it works"],
            "extra_field": "ignored",
        }
        code, out, _ = self._run(meta)
        self.assertEqual(code, 0)
        self.assertNotIn("commit_message", out)
        self.assertNotIn("acceptance", out)
        self.assertNotIn("extra_field", out)

    def test_none_values_filtered(self) -> None:
        meta = {"task_id": "t1", "owner": "dev", "capability": None}
        code, out, _ = self._run(meta)
        self.assertEqual(code, 0)
        self.assertNotIn("capability", out)

    def test_non_dict_input_rejected(self) -> None:
        code, _, err = self._run(["not", "a", "dict"])
        self.assertNotEqual(code, 0)
        self.assertIn("JSON object", err)

    def test_stages_included(self) -> None:
        meta = {
            "task_id": "t1",
            "owner": "dev",
            "stages": [{"stage_id": "s1", "objective": "do stuff"}],
        }
        code, out, _ = self._run(meta)
        self.assertEqual(code, 0)
        self.assertIn("stages", out)
        self.assertIn("stage_id", out)


if __name__ == "__main__":
    unittest.main()
