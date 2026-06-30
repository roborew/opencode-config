#!/usr/bin/env python3
"""Extract sections and opencode-task-json from a GitHub issue body (stdin → JSON stdout)."""
from __future__ import annotations

import json
import re
import sys


def section(body: str, name: str) -> str | None:
    pattern = rf"^## {re.escape(name)}\s*\n+(.*?)(?=^## |\Z)"
    m = re.search(pattern, body, re.MULTILINE | re.DOTALL)
    return m.group(1).strip() if m else None


def extract_json_block(body: str) -> dict | None:
    m = re.search(r"```opencode-task-json\s*\n(.*?)\n```", body, re.DOTALL)
    if not m:
        return None
    try:
        return json.loads(m.group(1))
    except json.JSONDecodeError:
        return None


def is_placeholder(text: str | None) -> bool:
    if not text:
        return True
    t = text.strip()
    return t.startswith("_") and ("issue-expand" in t or "To be completed" in t)


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
