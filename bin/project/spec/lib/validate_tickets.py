#!/usr/bin/env python3
"""Validate PRD tickets against docs/agents/repos.md registry.

Reads ticket JSON array on stdin; registry YAML path as first arg.
Prints validation errors to stderr and exits non-zero on failure.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

try:
    import yaml  # type: ignore
except ImportError:
    yaml = None


def load_registry(path: Path) -> list[dict]:
    text = path.read_text(encoding="utf-8")

    m = re.search(r"(?ms)^repos:\s*\n(.*)$", text)
    if m and yaml is not None:
        try:
            data = yaml.safe_load("repos:\n" + m.group(1))
            if isinstance(data, dict) and isinstance(data.get("repos"), list):
                return [r for r in data["repos"] if isinstance(r, dict)]
        except yaml.YAMLError:
            pass

    parts = text.split("---")
    if len(parts) >= 2:
        tail = parts[-1].strip()
        if re.match(r"^-\s*(repo|name):", tail):
            if yaml is not None:
                try:
                    loaded = yaml.safe_load(tail)
                    if isinstance(loaded, list):
                        return [r for r in loaded if isinstance(r, dict)]
                except yaml.YAMLError:
                    pass
            return _parse_repos_minimal(tail)

    if yaml is not None:
        try:
            data = yaml.safe_load(text) or {}
            repos = data.get("repos") or []
            if isinstance(repos, list) and repos:
                return [r for r in repos if isinstance(r, dict)]
        except yaml.YAMLError:
            pass

    return _parse_repos_minimal(text)


def _parse_repos_minimal(body: str) -> list[dict]:
    repos: list[dict] = []
    current: dict | None = None
    list_key: str | None = None
    for raw in body.splitlines():
        line = raw.rstrip()
        if line.strip().startswith("#") or not line.strip():
            continue
        if re.match(r"^repos:\s*\[\]\s*$", line):
            return []
        m_repo = re.match(r"^\s*-\s*repo:\s*(.+)$", line)
        if m_repo:
            if current:
                repos.append(current)
            current = {"repo": m_repo.group(1).strip().strip('"').strip("'"), "capabilities": [], "non_goals": []}
            list_key = None
            continue
        if current is None:
            continue
        m_kv = re.match(r"^\s{4}(\w+):\s*(.+)$", line)
        if m_kv:
            key, val = m_kv.group(1), m_kv.group(2).strip().strip('"').strip("'")
            if key in ("capabilities", "non_goals", "default_test_commands", "integration_contracts"):
                list_key = key
                current.setdefault(key, [])
            else:
                current[key] = val
                list_key = None
            continue
        m_item = re.match(r"^\s{6}-\s+(.+)$", line)
        if m_item and list_key:
            current.setdefault(list_key, []).append(m_item.group(1).strip().strip('"').strip("'"))
    if current:
        repos.append(current)
    return repos


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", s.strip().lower())


def capability_mismatch(capability: str, repo_entry: dict) -> str | None:
    caps = [norm(c) for c in repo_entry.get("capabilities") or []]
    non = [norm(c) for c in repo_entry.get("non_goals") or []]
    cap_n = norm(capability)
    if not cap_n:
        return None
    if cap_n in non:
        return f"capability '{capability}' is listed as non_goal for {repo_entry.get('repo')}"
    if caps and not any(cap_n == c or cap_n in c or c in cap_n for c in caps):
        return (
            f"capability '{capability}' not in declared capabilities for {repo_entry.get('repo')}: "
            + ", ".join(repo_entry.get("capabilities") or [])
        )
    return None


def main() -> None:
    if len(sys.argv) < 2:
        print("usage: validate_tickets.py <registry.md>", file=sys.stderr)
        sys.exit(1)
    registry_path = Path(sys.argv[1])
    tickets = json.load(sys.stdin)
    if not isinstance(tickets, list):
        print("tickets must be a JSON array", file=sys.stderr)
        sys.exit(1)

    if not registry_path.is_file():
        print(f"missing registry: {registry_path}", file=sys.stderr)
        sys.exit(4)

    registry = load_registry(registry_path)
    if not registry:
        print(
            "repo registry is empty (docs/agents/repos.md). "
            "Fill application_role and capabilities for each target repo before fanout.",
            file=sys.stderr,
        )
        sys.exit(5)

    by_repo = {r.get("repo"): r for r in registry if r.get("repo")}
    errors: list[str] = []

    for t in tickets:
        tid = t.get("id") or "<unknown>"
        repo = t.get("repo") or ""
        if not repo:
            errors.append(f"ticket {tid}: missing repo")
            continue
        entry = by_repo.get(repo)
        if not entry:
            errors.append(
                f"ticket {tid}: repo '{repo}' not in docs/agents/repos.md "
                f"(known: {', '.join(sorted(by_repo))})"
            )
            continue
        capability = t.get("capability") or t.get("role") or ""
        if not capability:
            errors.append(
                f"ticket {tid}: missing capability (must map to a declared repo capability)"
            )
            continue
        msg = capability_mismatch(capability, entry)
        if msg:
            errors.append(f"ticket {tid}: {msg}")
        owner = t.get("owner") or ""
        expected = entry.get("agent_owner") or ""
        if owner and expected:
            allowed = expected if isinstance(expected, list) else [expected]
            if owner not in allowed:
                errors.append(
                    f"ticket {tid}: owner '{owner}' not in registry agent_owner {allowed} for {repo}"
                )

    if errors:
        for e in errors:
            print(e, file=sys.stderr)
        sys.exit(6)

    print("ok")


if __name__ == "__main__":
    main()
