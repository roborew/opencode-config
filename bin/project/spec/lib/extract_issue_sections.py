#!/usr/bin/env python3
"""Extract sections and opencode-task-yaml from a GitHub issue body (stdin → JSON stdout)."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

# Import shared section extraction from issue_contract
sys.path.insert(0, str(Path(__file__).parent))
from issue_contract import extract_section as section
from issue_contract import is_placeholder


def extract_json_block(body: str) -> dict | None:
    m = re.search(r"```opencode-task-yaml\s*\n(.*?)\n```", body, re.DOTALL)
    if not m:
        return None
    try:
        import yaml
        parsed = yaml.safe_load(m.group(1))
        return parsed if isinstance(parsed, dict) else None
    except (ValueError, ImportError):
        return None


def main() -> None:
    body = sys.stdin.read()
    meta = extract_json_block(body) or {}
    out = {
        "meta": meta,
        "user_stories_covered": section(body, "User stories covered"),
        "implementation_plan": section(body, "Implementation plan"),
        "preserve_user_stories": False,
        "preserve_implementation_plan": False,
        "preserve_stages": bool(meta.get("stages")),
    }
    us = out["user_stories_covered"]
    ip = out["implementation_plan"]
    if us and not is_placeholder(us):
        out["preserve_user_stories"] = True
    if ip and not is_placeholder(ip):
        out["preserve_implementation_plan"] = True
    json.dump(out, sys.stdout)


if __name__ == "__main__":
    main()
