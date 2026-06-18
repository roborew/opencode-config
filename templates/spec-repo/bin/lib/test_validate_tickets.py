#!/usr/bin/env python3
"""Tests for validate_tickets.py — registry loading, capability matching, and ticket validation."""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

LIB = Path(__file__).resolve().parent
sys.path.insert(0, str(LIB))

import validate_tickets as vt  # noqa: E402


REGISTRY_YAML = """\
# Repos

---

repos:
  - repo: org/web
    application_role: User-facing web
    agent_owner: frontend-dev
    capabilities:
      - billing UI
      - admin dashboard
    non_goals:
      - push notifications
  - repo: org/api
    application_role: Backend API
    agent_owner: developer
    capabilities:
      - auth service
"""


class LoadRegistryTests(unittest.TestCase):
    def _write(self, content: str) -> Path:
        f = tempfile.NamedTemporaryFile(suffix=".md", delete=False, mode="w")
        f.write(content)
        f.close()
        return Path(f.name)

    def test_yaml_registry_parses(self) -> None:
        p = self._write(REGISTRY_YAML)
        result = vt.load_registry(p)
        self.assertEqual(len(result), 2)
        self.assertEqual(result[0].get("repo"), "org/web")
        self.assertEqual(result[1].get("repo"), "org/api")
        p.unlink(missing_ok=True)

    def test_empty_repos_list(self) -> None:
        p = self._write("repos: []\n")
        result = vt.load_registry(p)
        self.assertEqual(result, [])
        p.unlink(missing_ok=True)

    def test_bare_yaml_list_after_separator(self) -> None:
        content = "# Header\n\n---\n\n- repo: org/web\n    application_role: web\n"
        p = self._write(content)
        result = vt.load_registry(p)
        self.assertTrue(len(result) >= 1)
        self.assertEqual(result[0].get("repo"), "org/web")
        p.unlink(missing_ok=True)


class NormTests(unittest.TestCase):
    def test_normalizes_whitespace(self) -> None:
        self.assertEqual(vt.norm("  Hello   World  "), "hello world")

    def test_empty_string(self) -> None:
        self.assertEqual(vt.norm(""), "")


class CapabilityMismatchTests(unittest.TestCase):
    def test_exact_match_returns_none(self) -> None:
        entry = {"repo": "org/web", "capabilities": ["billing UI"]}
        self.assertIsNone(vt.capability_mismatch("billing UI", entry))

    def test_non_goal_returns_error(self) -> None:
        entry = {"repo": "org/web", "capabilities": ["billing UI"], "non_goals": ["push notifications"]}
        result = vt.capability_mismatch("push notifications", entry)
        self.assertIn("non_goal", result)

    def test_missing_capability_returns_error(self) -> None:
        entry = {"repo": "org/web", "capabilities": ["billing UI"]}
        result = vt.capability_mismatch("email sending", entry)
        self.assertIn("not in declared capabilities", result)

    def test_empty_capability_returns_none(self) -> None:
        entry = {"repo": "org/web", "capabilities": ["billing UI"]}
        self.assertIsNone(vt.capability_mismatch("", entry))

    def test_empty_capabilities_list_returns_none(self) -> None:
        entry = {"repo": "org/web", "capabilities": []}
        self.assertIsNone(vt.capability_mismatch("anything", entry))

    def test_substring_match_accepted(self) -> None:
        entry = {"repo": "org/web", "capabilities": ["billing UI and payments"]}
        self.assertIsNone(vt.capability_mismatch("billing UI", entry))


class ParseReposMinimalTests(unittest.TestCase):
    def test_parses_basic_repo_entry(self) -> None:
        body = "- repo: org/app\n    application_role: Web app\n"
        result = vt._parse_repos_minimal(body)
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["repo"], "org/app")
        self.assertEqual(result[0]["application_role"], "Web app")

    def test_parses_capabilities_list(self) -> None:
        body = "- repo: org/app\n    capabilities: list\n      - auth\n      - dashboard\n"
        result = vt._parse_repos_minimal(body)
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["capabilities"], ["auth", "dashboard"])

    def test_multiple_repos(self) -> None:
        body = "- repo: org/web\n    application_role: web\n- repo: org/api\n    application_role: api\n"
        result = vt._parse_repos_minimal(body)
        self.assertEqual(len(result), 2)

    def test_empty_repos_brackets(self) -> None:
        result = vt._parse_repos_minimal("repos: []\n")
        self.assertEqual(result, [])


if __name__ == "__main__":
    unittest.main()
