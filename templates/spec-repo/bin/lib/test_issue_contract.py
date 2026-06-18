#!/usr/bin/env python3
"""Tests for issue_contract.py — section extraction, placeholder detection, implementation plan analysis."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

LIB = Path(__file__).resolve().parent
sys.path.insert(0, str(LIB))

import issue_contract as ic  # noqa: E402


SAMPLE_BODY = """\
## Context

This is the context section.

## Goal

Ship the feature.

## Implementation planning

### Context

Some implementation context here.

### Current state

The current state description.

### Stage plan

Stage 1: Do something.

### Tests

Test plan here.

### Files to change

- file1.py
- file2.py

## Other section

More stuff.
"""

LEGACY_BODY = """\
## Implementation plan

This is a detailed legacy implementation plan that spans well over one hundred and twenty characters \
so it qualifies as substantive content for the purposes of the is_placeholder check logic.

## Other

Done.
"""


class ExtractSectionTests(unittest.TestCase):
    def test_extracts_existing_section(self) -> None:
        result = ic.extract_section(SAMPLE_BODY, "Context")
        self.assertEqual(result, "This is the context section.")

    def test_extracts_goal_section(self) -> None:
        result = ic.extract_section(SAMPLE_BODY, "Goal")
        self.assertEqual(result, "Ship the feature.")

    def test_returns_none_for_missing_section(self) -> None:
        result = ic.extract_section(SAMPLE_BODY, "Nonexistent")
        self.assertIsNone(result)

    def test_last_section_captured(self) -> None:
        result = ic.extract_section(SAMPLE_BODY, "Other section")
        self.assertEqual(result, "More stuff.")


class IsPlaceholderTests(unittest.TestCase):
    def test_none_is_placeholder(self) -> None:
        self.assertTrue(ic.is_placeholder(None))

    def test_empty_string_is_placeholder(self) -> None:
        self.assertTrue(ic.is_placeholder(""))

    def test_whitespace_is_placeholder(self) -> None:
        self.assertTrue(ic.is_placeholder("   "))

    def test_marker_text_is_placeholder(self) -> None:
        self.assertTrue(ic.is_placeholder("_Map PRD user stories to implementation tasks"))

    def test_issue_expand_marker(self) -> None:
        self.assertTrue(ic.is_placeholder("Run issue-expand` in the implementation repo"))

    def test_real_text_not_placeholder(self) -> None:
        self.assertFalse(ic.is_placeholder("Implement the auth flow using JWT tokens"))


class ImplementationPlanTextTests(unittest.TestCase):
    def test_returns_implementation_planning_section(self) -> None:
        result = ic.implementation_plan_text(SAMPLE_BODY)
        self.assertIn("Context", result)
        self.assertIn("Stage plan", result)

    def test_prefers_longer_legacy_plan(self) -> None:
        result = ic.implementation_plan_text(LEGACY_BODY)
        self.assertIn("legacy implementation plan", result)

    def test_empty_body_returns_empty(self) -> None:
        result = ic.implementation_plan_text("")
        self.assertEqual(result, "")


class HasSubstantiveImplPlanningTests(unittest.TestCase):
    def test_complete_plan_passes(self) -> None:
        ok, missing = ic.has_substantive_impl_planning(SAMPLE_BODY)
        self.assertTrue(ok)

    def test_empty_body_fails(self) -> None:
        ok, missing = ic.has_substantive_impl_planning("")
        self.assertFalse(ok)
        self.assertEqual(len(missing), len(ic.IMPL_PLAN_HEADINGS))

    def test_legacy_long_plan_passes(self) -> None:
        ok, missing = ic.has_substantive_impl_planning(LEGACY_BODY)
        self.assertTrue(ok)

    def test_placeholder_body_fails(self) -> None:
        body = "## Implementation planning\n\n_To be completed by the agent\n"
        ok, missing = ic.has_substantive_impl_planning(body)
        self.assertFalse(ok)

    def test_partial_headings_reports_missing(self) -> None:
        body = "## Implementation planning\n\n### Context\n\nSome context.\n\n### Tests\n\nSome tests.\n"
        ok, missing = ic.has_substantive_impl_planning(body)
        self.assertIn("Current state", missing)
        self.assertIn("Stage plan", missing)


if __name__ == "__main__":
    unittest.main()
