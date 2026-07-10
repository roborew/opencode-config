#!/usr/bin/env python3
"""Find existing GitHub child issues for fanout idempotency and audit."""
from __future__ import annotations

import json
import re
import subprocess
import sys
from dataclasses import dataclass


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
        "number,title,body,state",
    ]
    if label:
        cmd.extend(["--label", label])
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.DEVNULL, text=True)
    except subprocess.CalledProcessError:
        return []
    data = json.loads(out or "[]")
    return data if isinstance(data, list) else []


def find_all(repo: str, slug: str, title: str, task_id: str) -> list[dict]:
    label = f"feature:{slug}"
    patterns = task_id_patterns(task_id)
    matches: list[dict] = []
    seen: set[int] = set()
    for use_label in (True, False):
        issues = list_issues(repo, label if use_label else None)
        for issue in issues:
            num = issue.get("number")
            if not isinstance(num, int) or num in seen:
                continue
            if issue_matches(issue, title, patterns):
                seen.add(num)
                matches.append(issue)
    matches.sort(key=lambda i: i.get("number") or 0)
    return matches


def find_existing(repo: str, slug: str, title: str, task_id: str) -> int | None:
    matches = find_all(repo, slug, title, task_id)
    if not matches:
        return None
    return matches[0]["number"]


@dataclass
class TicketAudit:
    ticket_id: str
    repo: str
    title: str
    matches: list[dict]

    @property
    def status(self) -> str:
        count = len(self.matches)
        if count == 0:
            return "MISSING"
        if count == 1:
            return "OK"
        return "DUPLICATE"


def audit_tickets(slug: str, tickets: list[dict]) -> tuple[list[TicketAudit], list[dict]]:
    rows: list[TicketAudit] = []
    matched_numbers: set[int] = set()
    for ticket in tickets:
        tid = str(ticket.get("id") or "")
        repo = str(ticket.get("repo") or "")
        title = str(ticket.get("title") or "")
        matches = find_all(repo, slug, title, tid)
        for issue in matches:
            num = issue.get("number")
            if isinstance(num, int):
                matched_numbers.add(num)
        rows.append(TicketAudit(ticket_id=tid, repo=repo, title=title, matches=matches))

    orphans: list[dict] = []
    repos = sorted({row.repo for row in rows if row.repo})
    label = f"feature:{slug}"
    for repo in repos:
        for issue in list_issues(repo, label):
            num = issue.get("number")
            if isinstance(num, int) and num not in matched_numbers:
                orphans.append({"repo": repo, **issue})
    orphans.sort(key=lambda i: (i.get("repo") or "", i.get("number") or 0))
    return rows, orphans


def print_audit(slug: str, tickets: list[dict]) -> int:
    rows, orphans = audit_tickets(slug, tickets)
    problems = 0
    print(f"==> fanout audit: {slug} ({len(rows)} tickets)")
    for row in rows:
        nums = ", ".join(f"#{m['number']}" for m in row.matches) or "(none)"
        print(f"{row.status:9} {row.ticket_id:20} {row.repo}  {nums}  {row.title}")
        if row.status != "OK":
            problems += 1
    if orphans:
        problems += len(orphans)
        print("ORPHAN issues (feature label but no PRD ticket match):")
        for issue in orphans:
            print(
                f"  ORPHAN  {issue['repo']}#{issue['number']} [{issue.get('state', '?')}] "
                f"{issue.get('title', '')}"
            )
    if problems:
        print(
            f"\nFAIL: {problems} problem(s). Do not run gh issue create.",
            file=sys.stderr,
        )
        print(
            "Run bin/fanout <slug> to create missing issues (skips existing).",
            file=sys.stderr,
        )
        print(
            "Close duplicate/orphan issues, then bin/fanout-audit <slug> until clean.",
            file=sys.stderr,
        )
        return 1
    print("PASS: one issue per ticket, no orphans.")
    return 0


def main() -> None:
    if len(sys.argv) >= 2 and sys.argv[1] == "audit":
        if len(sys.argv) != 4:
            print("usage: existing_issue.py audit <slug> <tickets.json>", file=sys.stderr)
            sys.exit(2)
        slug = sys.argv[2]
        tickets_path = sys.argv[3]
        tickets = json.loads(open(tickets_path, encoding="utf-8").read())
        if not isinstance(tickets, list):
            print("tickets json must be an array", file=sys.stderr)
            sys.exit(2)
        sys.exit(print_audit(slug, tickets))

    if len(sys.argv) >= 2 and sys.argv[1] == "find-all":
        if len(sys.argv) != 6:
            print(
                "usage: existing_issue.py find-all <repo> <slug> <title> <task_id>",
                file=sys.stderr,
            )
            sys.exit(2)
        repo, slug, title, task_id = sys.argv[2:6]
        for issue in find_all(repo, slug, title, task_id):
            print(issue["number"])
        return

    if len(sys.argv) != 5:
        print(
            "usage: existing_issue.py <repo> <slug> <title> <task_id>",
            file=sys.stderr,
        )
        print("       existing_issue.py find-all <repo> <slug> <title> <task_id>", file=sys.stderr)
        print("       existing_issue.py audit <slug> <tickets.json>", file=sys.stderr)
        sys.exit(2)
    repo, slug, title, task_id = sys.argv[1:5]
    num = find_existing(repo, slug, title, task_id)
    if num is not None:
        print(num)


if __name__ == "__main__":
    main()
