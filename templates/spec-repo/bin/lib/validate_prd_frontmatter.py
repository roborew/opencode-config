#!/usr/bin/env python3
"""Validate PRD markdown frontmatter before fanout.

Usage: validate_prd_frontmatter.py <docs/prd/slug.md>
Exits 0 when frontmatter YAML parses and required ticket fields are present.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

try:
    import yaml  # type: ignore
except ImportError:
    yaml = None


def extract_frontmatter(text: str) -> str:
    if not text.startswith("---"):
        raise ValueError("PRD must start with --- frontmatter delimiter")
    end = text.index("---", 3)
    return text[3:end]


def main() -> None:
    if len(sys.argv) < 2:
        print("usage: validate_prd_frontmatter.py <prd.md>", file=sys.stderr)
        sys.exit(1)
    path = Path(sys.argv[1])
    if not path.is_file():
        print(f"missing: {path}", file=sys.stderr)
        sys.exit(2)

    text = path.read_text(encoding="utf-8")
    try:
        block = extract_frontmatter(text)
    except ValueError as e:
        print(str(e), file=sys.stderr)
        sys.exit(3)

    if yaml is None:
        print("PyYAML required", file=sys.stderr)
        sys.exit(4)

    try:
        data = yaml.safe_load(block) or {}
    except yaml.YAMLError as e:
        print(f"invalid YAML frontmatter: {e}", file=sys.stderr)
        sys.exit(5)

    tickets = data.get("tickets") or []
    if not isinstance(tickets, list) or not tickets:
        print("tickets: must be a non-empty list", file=sys.stderr)
        sys.exit(6)

    errors: list[str] = []
    for t in tickets:
        tid = t.get("id") or "<unknown>"
        for field in ("repo", "capability", "title", "owner", "acceptance"):
            val = t.get(field)
            if not val:
                errors.append(f"ticket {tid}: missing {field}")
            elif field == "acceptance" and isinstance(val, list) and len(val) == 0:
                errors.append(f"ticket {tid}: acceptance must be non-empty")
        cm = str(t.get("commit_message") or "")
        if cm and ":" in cm:
            pattern = rf"(?m)^\s*commit_message:\s*{re.escape(cm)}\s*$"
            if re.search(pattern, block) and not re.search(
                rf'(?m)^\s*commit_message:\s*["\']{re.escape(cm)}["\']\s*$', block
            ):
                errors.append(
                    f"ticket {tid}: commit_message must be quoted (contains ':'): {cm!r}"
                )

    if errors:
        for e in errors:
            print(e, file=sys.stderr)
        sys.exit(7)

    print(f"ok ({len(tickets)} tickets)")


if __name__ == "__main__":
    main()
