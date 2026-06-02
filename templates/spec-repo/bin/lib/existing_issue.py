#!/usr/bin/env python3
"""Find an existing GitHub child issue for fanout idempotency."""
from __future__ import annotations

import json
import re
import subprocess
import sys


def task_id_patterns(task_id: str) -> list[re.Pattern[str]]:
    if not task_id:
        return []
    escaped = re.escape(task_id)
    return [
        re.compile(rf'"task_id"\s*:\s*"{escaped}"'),
        re.compile(rf"task_id\s*:\s*\"?{escaped}\"?", re.IGNORECASE),
        re.compile(rf"\*\*Task ID:\*\*\s*{escaped}\b", re.IGNORECASE),
    ]


def issue_matches(issue: dict, title: str, patterns: list[re.Pattern[str]]) -> bool:
    if issue.get("title") == title:
        return True
    body = issue.get("body") or ""
    return any(p.search(body) for p in patterns)


def list_issues(repo: str, label: str | None) -> list[dict]:
    cmd = [
        "gh",
        "issue",
        "list",
        "--repo",
        repo,
        "--state",
        "all",
        "--limit",
        "200",
        "--json",
        "number,title,body",
    ]
    if label:
        cmd.extend(["--label", label])
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.DEVNULL, text=True)
    except subprocess.CalledProcessError:
        return []
    data = json.loads(out or "[]")
    return data if isinstance(data, list) else []


def find_existing(repo: str, slug: str, title: str, task_id: str) -> int | None:
    label = f"feature:{slug}"
    patterns = task_id_patterns(task_id)
    seen: set[int] = set()
    for use_label in (True, False):
        issues = list_issues(repo, label if use_label else None)
        for issue in issues:
            num = issue.get("number")
            if not isinstance(num, int) or num in seen:
                continue
            seen.add(num)
            if issue_matches(issue, title, patterns):
                return num
    return None


def main() -> None:
    if len(sys.argv) != 5:
        print(
            "usage: existing_issue.py <repo> <slug> <title> <task_id>",
            file=sys.stderr,
        )
        sys.exit(2)
    repo, slug, title, task_id = sys.argv[1:5]
    num = find_existing(repo, slug, title, task_id)
    if num is not None:
        print(num)


if __name__ == "__main__":
    main()
