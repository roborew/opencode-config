#!/usr/bin/env python3
"""Validate a fanout child issue body against the production issue-expand contract.

Usage:
  validate_issue_body.py --level fanout|expand|orchestrate [--task-id ID] < issue-body.md
  validate_issue_body.py --level expand --file /path/to/body.md

Exit 0 = pass; 1 = fail (errors on stderr as JSON lines).
"""
from __future__ import annotations

import argparse
import re
import sys
from typing import Any

try:
    import yaml  # type: ignore
except ImportError:
    yaml = None


PLACEHOLDER_MARKERS = (
    "_Map PRD user stories",
    "_Add files, TDD order",
    "_To be completed",
    "issue-expand` in the implementation",
)


def extract_section(body: str, name: str) -> str | None:
    pattern = rf"^## {re.escape(name)}\s*\n+(.*?)(?=^## |\Z)"
    m = re.search(pattern, body, re.MULTILINE | re.DOTALL)
    return m.group(1).strip() if m else None


def extract_meta(body: str) -> dict[str, Any] | None:
    m = re.search(r"```opencode-task-yaml\s*\n(.*?)\n```", body, re.DOTALL)
    if not m:
        return None
    try:
        parsed = yaml.safe_load(m.group(1)) if yaml else None
        return parsed if isinstance(parsed, dict) else None
    except (TypeError, ValueError):
        return None


def is_placeholder(text: str | None) -> bool:
    if not text or not text.strip():
        return True
    return any(marker in text for marker in PLACEHOLDER_MARKERS)


def validate(body: str, level: str, expected_task_id: str | None) -> list[str]:
    errors: list[str] = []

    if not re.search(r"^Parent PRD:\s*https://github\.com/", body, re.MULTILINE):
        errors.append("missing Parent PRD GitHub URL")

    meta = extract_meta(body)
    if meta is None:
        errors.append("missing or invalid opencode-task-yaml block")
        meta = {}

    if level in ("fanout", "expand", "orchestrate"):
        if not meta.get("task_id"):
            errors.append("opencode-task-yaml missing task_id")
        elif expected_task_id and meta.get("task_id") != expected_task_id:
            errors.append(f"task_id mismatch: expected {expected_task_id}, got {meta.get('task_id')}")

        for field in ("owner", "commit_message", "acceptance", "test_commands"):
            if field not in meta:
                errors.append(f"opencode-task-yaml missing {field}")
        if meta.get("owner") not in {"developer", "frontend-dev", "ux-dev"}:
            errors.append("opencode-task owner must be developer, frontend-dev, or ux-dev")
        if meta.get("design_delivery") not in (None, "brief-only", "prototype-required"):
            errors.append("design_delivery must be brief-only or prototype-required")

    us = extract_section(body, "User stories covered")
    ip = extract_section(body, "Implementation plan")

    if level == "fanout":
        if us is None:
            errors.append("missing ## User stories covered")
        if ip is None:
            errors.append("missing ## Implementation plan")
        return errors

    if us is None or is_placeholder(us):
        errors.append("User stories covered missing or still placeholder")
    if ip is None or is_placeholder(ip):
        errors.append("Implementation plan missing or still placeholder")

    stages = meta.get("stages") if isinstance(meta, dict) else None
    if not isinstance(stages, list) or len(stages) == 0:
        errors.append("opencode-task-yaml missing non-empty stages[]")
    else:
        for i, stage in enumerate(stages):
            if not isinstance(stage, dict):
                errors.append(f"stages[{i}] is not an object")
                continue
            for sf in ("stage_id", "owner", "objective", "acceptance", "test_commands", "commit_message"):
                if sf not in stage:
                    errors.append(f"stages[{i}] missing {sf}")
            if stage.get("owner") not in {"developer", "frontend-dev", "ux-dev"}:
                errors.append(f"stages[{i}] owner must be developer, frontend-dev, or ux-dev")

    return errors


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--level", choices=("fanout", "expand", "orchestrate"), default="expand")
    parser.add_argument("--task-id", default=None)
    parser.add_argument("--file", default=None)
    args = parser.parse_args()

    if args.file:
        body = open(args.file, encoding="utf-8").read()
    else:
        body = sys.stdin.read()

    # orchestrate uses same bar as expand
    level = "expand" if args.level == "orchestrate" else args.level
    errors = validate(body, level, args.task_id)

    if errors:
        for e in errors:
            print(e, file=sys.stderr)
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
