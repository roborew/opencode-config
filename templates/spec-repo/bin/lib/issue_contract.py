#!/usr/bin/env python3
"""Shared GitHub issue body sections and placeholders (spec + impl phases)."""
from __future__ import annotations

import re

PLACEHOLDER_MARKERS = (
    "_Map PRD user stories",
    "_Add files, TDD order",
    "_To be completed",
    "_Pending in this repository",
    "issue-expand` in the implementation",
    "issue-expand** to produce",
)

IMPL_PLAN_HEADINGS = (
    "Context",
    "Goal",
    "Current state",
    "Stage plan",
    "Tests",
    "Files to change",
)

LEGACY_PLAN_HEADING = "Implementation plan"
IMPL_PLANNING_HEADING = "Implementation planning"


def extract_section(body: str, name: str) -> str | None:
    pattern = rf"^## {re.escape(name)}\s*\n+(.*?)(?=^## |\Z)"
    m = re.search(pattern, body, re.MULTILINE | re.DOTALL)
    return m.group(1).strip() if m else None


def is_placeholder(text: str | None) -> bool:
    if not text or not text.strip():
        return True
    return any(marker in text for marker in PLACEHOLDER_MARKERS)


def implementation_plan_text(body: str) -> str:
    ip = extract_section(body, IMPL_PLANNING_HEADING) or ""
    legacy = extract_section(body, LEGACY_PLAN_HEADING) or ""
    if legacy and not is_placeholder(legacy) and len(legacy) > len(ip):
        return legacy
    return ip


def has_substantive_impl_planning(body: str) -> tuple[bool, list[str]]:
    ip = implementation_plan_text(body)
    legacy = extract_section(body, LEGACY_PLAN_HEADING)

    if legacy and not is_placeholder(legacy) and len(legacy.strip()) >= 120:
        return True, []

    if not ip or is_placeholder(ip):
        return False, list(IMPL_PLAN_HEADINGS)

    missing: list[str] = []
    required = {"Context", "Current state", "Stage plan", "Tests"}
    found = 0
    for heading in IMPL_PLAN_HEADINGS:
        pattern = rf"^###?\s+.*{re.escape(heading)}|^\*\*{re.escape(heading)}\*\*"
        if re.search(pattern, ip, re.MULTILINE | re.IGNORECASE):
            found += 1
        else:
            missing.append(heading)

    for h in required:
        pattern = rf"^###?\s+.*{re.escape(h)}|^\*\*{re.escape(h)}\*\*"
        if not re.search(pattern, ip, re.MULTILINE | re.IGNORECASE) and h not in missing:
            missing.append(h)

    ok = found >= 3 and len(missing) <= 2
    return ok, missing
