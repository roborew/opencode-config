#!/usr/bin/env python3
"""Parse opencode-task-yaml or legacy opencode-task-json from a GitHub issue body."""
from __future__ import annotations

import json
import re
import sys
from typing import Any

try:
    import yaml  # type: ignore
except ImportError:
    yaml = None


def extract_task_block_raw(body: str) -> tuple[str, str] | None:
    for fence in ("opencode-task-yaml", "opencode-task-json"):
        m = re.search(rf"```{{1}}{fence}\s*\n(.*?)\n```", body, re.DOTALL)
        if m:
            return fence, m.group(1).strip()
    return None


def parse_task_meta(body: str) -> dict[str, Any] | None:
    raw = extract_task_block_raw(body)
    if not raw:
        return None
    fence, content = raw
    if not content:
        return None
    try:
        if fence == "opencode-task-json":
            data = json.loads(content)
        else:
            if yaml is None:
                return None
            data = yaml.safe_load(content)
        return data if isinstance(data, dict) else None
    except (json.JSONDecodeError, yaml.YAMLError):
        return None


def main() -> None:
    body = sys.stdin.read() if len(sys.argv) < 2 else open(sys.argv[1], encoding="utf-8").read()
    meta = parse_task_meta(body)
    if meta is None:
        print("null")
        sys.exit(1)
    print(json.dumps(meta))
    sys.exit(0)


if __name__ == "__main__":
    main()
