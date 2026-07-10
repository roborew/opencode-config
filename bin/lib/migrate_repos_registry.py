#!/usr/bin/env python3
"""Migrate docs/agents/repos.md to the repo-aware registry schema."""
from __future__ import annotations

import re
import sys
from pathlib import Path

try:
    import yaml  # type: ignore
except ImportError:
    yaml = None

HEADER = """# Application repo registry

Agents **must** read this file before authoring PRD `tickets:` or running `bin/fanout`. Do **not** infer backend/frontend from repo names (`api`, `web`, etc.). Use **`application_role`**, **`capabilities`**, and **`non_goals`** here; use **`CONTEXT.md`** for product vocabulary only.

## Schema

See the OpenCode config template `templates/spec-repo/docs/agents/repos.md` for field definitions.

## Consumer rules

1. **Before PRD ticket slicing:** Confirm every target repo is listed with filled `application_role` and `capabilities`.
2. **Before fanout:** Confirm this registry matches the feature. `bin/fanout` blocks when entries are incomplete.
3. **Per ticket:** Set `capability` to one entry from the target repo's `capabilities` list.
4. **Domain glossary:** `CONTEXT.md` defines terms; this file defines **topology**.

---

"""


def split_registry(path: Path) -> tuple[str, list[dict]]:
    text = path.read_text(encoding="utf-8")
    marker = "\nrepos:"
    idx = text.rfind(marker)
    if idx != -1:
        header = text[: idx + 1]
        body = text[idx + 1 :].lstrip()
        return _parse_registry_body(header, body)

    # Bare YAML list after --- (no repos: wrapper) — common in filled registries.
    sep = "\n---\n"
    sep_idx = text.rfind(sep)
    if sep_idx != -1:
        header = text[: sep_idx + len(sep)]
        body = text[sep_idx + len(sep) :].lstrip()
        if body.lstrip().startswith("- "):
            return _parse_registry_body(header, body)

    return text, []


def _parse_registry_body(header: str, body: str) -> tuple[str, list[dict]]:
    if yaml is not None:
        try:
            data = yaml.safe_load(body) or {}
            if isinstance(data, dict):
                repos = data.get("repos") or []
                if isinstance(repos, list):
                    parsed = [r for r in repos if isinstance(r, dict)]
                    if parsed:
                        return header, parsed
            if isinstance(data, list):
                parsed = [r for r in data if isinstance(r, dict)]
                if parsed:
                    return header, parsed
        except Exception:
            pass
    return header, _parse_repos_minimal(body)


def _parse_repos_minimal(body: str) -> list[dict]:
    repos: list[dict] = []
    current: dict | None = None
    list_key: str | None = None
    for raw in body.splitlines():
        line = raw.rstrip()
        if not line.strip() or line.strip().startswith("#"):
            continue
        if re.match(r"^\[\]\s*$", line.strip()):
            return []
        m_repo = re.match(r"^\s*-\s*repo:\s*(.+)$", line)
        m_name = re.match(r"^\s*-\s*name:\s*(.+)$", line)
        if m_repo or m_name:
            if current:
                repos.append(current)
            key = "repo" if m_repo else "name"
            val = (m_repo or m_name).group(1).strip().strip('"').strip("'")
            current = {key: val}
            list_key = None
            continue
        if current is None:
            continue
        m_kv = re.match(r"^\s{4}(\w+):\s*(.*)$", line)
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


def infer_defaults(repo: str) -> dict:
    base = repo.split("/")[-1].lower()
    if any(x in base for x in ("web", "frontend", "ui", "app")):
        return {
            "application_role": "TBD — user-facing application (confirm in setup-skills)",
            "agent_owner": "frontend-dev",
            "capabilities": ["TBD — add capabilities in setup-skills"],
            "non_goals": [],
        }
    if any(x in base for x in ("api", "service", "worker", "backend", "server")):
        return {
            "application_role": "TBD — service/API role (confirm — not necessarily generic backend)",
            "agent_owner": "developer",
            "capabilities": ["TBD — add capabilities in setup-skills"],
            "non_goals": [],
        }
    return {
        "application_role": "TBD — describe this repo's product role in setup-skills",
        "agent_owner": "developer",
        "capabilities": ["TBD — add capabilities in setup-skills"],
        "non_goals": [],
    }


def is_complete(entry: dict) -> bool:
    role = str(entry.get("application_role") or "")
    caps = entry.get("capabilities") or []
    if not entry.get("repo"):
        return False
    if "TBD" in role or not role.strip():
        return False
    if not caps or any("TBD" in str(c) for c in caps):
        return False
    return True


def is_empty_or_tbd(value: object) -> bool:
    if value is None:
        return True
    if isinstance(value, str):
        return not value.strip() or "TBD" in value
    if isinstance(value, list):
        return len(value) == 0
    return False


def clean_capabilities(caps: object) -> list:
    if not isinstance(caps, list):
        return []
    return [c for c in caps if c and "TBD" not in str(c)]


def needs_schema_migration(repos: list[dict]) -> bool:
    for r in repos:
        if not r.get("repo") and not r.get("name"):
            return True
        if "name" in r and "repo" not in r:
            return True
        if r.get("role") == "target" and "application_role" not in r:
            return True
    return False


def normalize_entry(raw: dict) -> dict:
    repo = raw.get("repo") or raw.get("name") or ""
    if not repo:
        return raw
    out: dict = {"repo": repo}
    defaults = infer_defaults(repo)

    role = raw.get("application_role")
    if not is_empty_or_tbd(role):
        out["application_role"] = role
    else:
        out["application_role"] = defaults["application_role"]

    owner = raw.get("agent_owner")
    if not is_empty_or_tbd(owner):
        out["agent_owner"] = owner
    else:
        out["agent_owner"] = defaults["agent_owner"]

    caps = clean_capabilities(raw.get("capabilities"))
    if caps:
        out["capabilities"] = caps
    else:
        out["capabilities"] = defaults["capabilities"]

    for key in ("non_goals", "integration_contracts", "default_test_commands"):
        val = raw.get(key)
        if val not in (None, "", []):
            out[key] = val
        elif key == "non_goals":
            out["non_goals"] = []

    return out


def dedupe_repos(repos: list[dict]) -> list[dict]:
    seen: set[str] = set()
    unique: list[dict] = []
    for r in repos:
        repo = r.get("repo")
        if not repo or repo in seen:
            continue
        seen.add(repo)
        unique.append(r)
    return unique


def format_registry_yaml(repos: list[dict]) -> str:
    if yaml is not None:
        body = yaml.safe_dump(repos, sort_keys=False, allow_unicode=True).rstrip()
        indented = "\n".join(f"  {line}" if line else line for line in body.splitlines())
        return f"repos:\n{indented}"
    lines = ["repos:"]
    for r in repos:
        lines.append(f"  - repo: {r['repo']}")
        for key in ("application_role", "agent_owner"):
            if key in r:
                lines.append(f"    {key}: {r[key]}")
        for list_key in ("capabilities", "non_goals", "integration_contracts", "default_test_commands"):
            if r.get(list_key):
                lines.append(f"    {list_key}:")
                for item in r[list_key]:
                    lines.append(f"      - {item}")
    return "\n".join(lines)


def registry_content(header: str, repos: list[dict]) -> str:
    h = header.rstrip() if header.strip() else HEADER.rstrip()
    return f"{h}\n\n{format_registry_yaml(repos)}\n"


def write_registry(path: Path, repos: list[dict], header: str | None = None) -> None:
    h = header if header is not None else HEADER
    path.write_text(registry_content(h, repos), encoding="utf-8")


def main() -> None:
    if len(sys.argv) < 2:
        print("usage: migrate_repos_registry.py <repos.md> [--check-only]", file=sys.stderr)
        sys.exit(2)
    path = Path(sys.argv[1])
    check_only = "--check-only" in sys.argv[2:]
    if not path.is_file():
        print(f"missing {path}", file=sys.stderr)
        sys.exit(1)

    header, repos = split_registry(path)
    if not repos:
        print("INCOMPLETE: repos list is empty")
        sys.exit(3)

    normalized = dedupe_repos([normalize_entry(r) for r in repos])

    if check_only:
        incomplete = [r.get("repo") or r.get("name") for r in repos if not is_complete(normalize_entry(r))]
        if incomplete:
            print("INCOMPLETE: " + ", ".join(str(x) for x in incomplete if x))
            sys.exit(3)
        print("ok")
        sys.exit(0)

    schema_migration = needs_schema_migration(repos)
    if schema_migration:
        old_content = path.read_text(encoding="utf-8")
        new_content = registry_content(header, normalized)
        if new_content != old_content:
            backup = path.with_suffix(path.suffix + ".bak")
            if not backup.exists():
                backup.write_text(old_content, encoding="utf-8")
            write_registry(path, normalized, header)
            print(f"migrated {path} ({len(normalized)} repos)")
        else:
            print(f"no migration needed for {path}")
    else:
        print(f"no migration needed for {path}")

    incomplete = [r["repo"] for r in normalized if not is_complete(r)]
    if incomplete:
        joined = ", ".join(incomplete)
        print(
            "NEXT: In OpenCode (architect → setup-project), fill application_role "
            f"and capabilities for: {joined}"
        )
        sys.exit(3)


if __name__ == "__main__":
    main()
