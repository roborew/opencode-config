#!/usr/bin/env python3
"""Tests for existing_issue.py matching and audit status logic."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

LIB = Path(__file__).resolve().parent
sys.path.insert(0, str(LIB))

import existing_issue as ei  # noqa: E402


class IssueMatchTests(unittest.TestCase):
    def test_title_match(self) -> None:
        issue = {"number": 1, "title": "Auth: login", "body": ""}
        self.assertTrue(ei.issue_matches(issue, "Auth: login", []))

    def test_yaml_task_id_in_yaml_fence(self) -> None:
        body = """```opencode-task-yaml
task_id: ses-client
owner: developer
```"""
        issue = {"number": 2, "title": "Other", "body": body}
        patterns = ei.task_id_patterns("ses-client")
        self.assertTrue(ei.issue_matches(issue, "Different title", patterns))

    def test_json_task_id(self) -> None:
        body = '{"task_id": "reset-flow"}'
        issue = {"number": 3, "title": "X", "body": body}
        patterns = ei.task_id_patterns("reset-flow")
        self.assertTrue(ei.issue_matches(issue, "X", patterns))

    def test_legacy_task_id_line(self) -> None:
        body = "**Task ID:** verify-email"
        issue = {"number": 4, "title": "Y", "body": body}
        patterns = ei.task_id_patterns("verify-email")
        self.assertTrue(ei.issue_matches(issue, "Y", patterns))


class TicketAuditTests(unittest.TestCase):
    def test_status_counts(self) -> None:
        ok = ei.TicketAudit("a", "org/r", "t", [{"number": 1}])
        missing = ei.TicketAudit("b", "org/r", "t", [])
        dup = ei.TicketAudit("c", "org/r", "t", [{"number": 2}, {"number": 3}])
        self.assertEqual(ok.status, "OK")
        self.assertEqual(missing.status, "MISSING")
        self.assertEqual(dup.status, "DUPLICATE")


if __name__ == "__main__":
    unittest.main()
