#!/usr/bin/env python3
"""Parse opencode-task-yaml or legacy opencode-task-json from a GitHub issue body.

Falls back to targeted-issue markdown (## What to build / ## Acceptance criteria) when
no fenced block exists. Use --embed to inject yaml into a targeted body before publish.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

try:
    import yaml  # type: ignore
except ImportError:
    yaml = None


def slugify(text: str, max_len: int = 56) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return s[:max_len].rstrip("-")


def extract_section(body: str, name: str) -> str | None:
    pattern = rf"^## {re.escape(name)}\s*\n+(.*?)(?=^## |\Z)"
    m = re.search(pattern, body, re.MULTILINE | re.DOTALL)
    return m.group(1).strip() if m else None


def parse_checkbox_items(section: str | None) -> list[str]:
    if not section:
        return []
    items: list[str] = []
    for line in section.splitlines():
        m = re.match(r"^\s*[-*]\s+\[[ xX]\]\s+(.*)$", line)
        if m:
            items.append(m.group(1).strip())
    return items


def parse_test_commands(body: str) -> list[str]:
    section = extract_section(body, "Test commands")
    if not section:
        return []
    cmds: list[str] = []
    for line in section.splitlines():
        m = re.match(r"^\s*[-*]\s+`([^`]+)`\s*$", line)
        if m:
            cmds.append(m.group(1).strip())
        elif line.strip().startswith("- "):
            cmds.append(line.strip()[2:].strip())
    return cmds


def parse_depends_on(body: str) -> list[str]:
    section = extract_section(body, "Blocked by")
    if not section:
        return []
    if re.search(r"\bnone\b", section, re.IGNORECASE):
        return []
    return [f"#{n}" for n in re.findall(r"#(\d+)", section)]


def make_task_id(title: str, feature_slug: str | None = None) -> str:
    base = slugify(title)
    if feature_slug:
        prefix = slugify(feature_slug, max_len=40)
        room = max(12, 60 - len(prefix) - 2)
        return f"{prefix}--{base[:room]}"
    return base


def infer_targeted_meta(body: str, title: str | None = None, feature_slug: str | None = None) -> dict[str, Any] | None:
    """Build flat orchestrate meta from targeted-issue markdown sections."""
    if not extract_section(body, "What to build") and not extract_section(body, "Acceptance criteria"):
        return None
    issue_title = (title or "").strip() or "targeted-change"
    acceptance = parse_checkbox_items(extract_section(body, "Acceptance criteria"))
    if not acceptance:
        what = extract_section(body, "What to build")
        if what:
            acceptance = [what.splitlines()[0].strip()[:200]]
    if not acceptance:
        return None
    owner_match = re.search(r"(?m)^\s*owner\s*:\s*(\S+)", body)
    owner = owner_match.group(1) if owner_match else "developer"
    commit_message = issue_title if len(issue_title) <= 72 else issue_title[:69] + "..."
    return {
        "task_id": make_task_id(issue_title, feature_slug),
        "owner": owner,
        "depends_on": parse_depends_on(body),
        "acceptance": acceptance,
        "test_commands": parse_test_commands(body),
        "commit_message": commit_message,
    }


def resolve_task_meta(body: str, title: str | None = None, feature_slug: str | None = None) -> dict[str, Any] | None:
    return parse_task_meta(body) or infer_targeted_meta(body, title=title, feature_slug=feature_slug)


def format_yaml_block(meta: dict[str, Any]) -> str:
    if yaml is None:
        raise RuntimeError("PyYAML required for embed")
    return yaml.dump(meta, default_flow_style=False, sort_keys=False).rstrip()


def embed_task_yaml_block(body: str, title: str, feature_slug: str | None = None) -> str:
    if extract_task_block_raw(body):
        return body
    meta = infer_targeted_meta(body, title=title, feature_slug=feature_slug)
    if meta is None:
        return body
    fence = (
        "## OpenCode task (machine-readable)\n"
        "```opencode-task-yaml\n"
        f"{format_yaml_block(meta)}\n"
        "```\n"
    )
    blocked = re.search(r"^## Blocked by\s*$", body, re.MULTILINE)
    if blocked:
        pos = blocked.start()
        return body[:pos].rstrip() + "\n\n" + fence + "\n" + body[pos:]
    return body.rstrip() + "\n\n" + fence + "\n"


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
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--embed", action="store_true", help="Inject opencode-task-yaml into targeted body")
    parser.add_argument("--title", default=None)
    parser.add_argument("--feature-slug", default=None)
    parser.add_argument("--in", dest="in_path", default=None)
    parser.add_argument("--out", dest="out_path", default=None)
    parser.add_argument("body_file", nargs="?", default=None)
    args = parser.parse_args()

    if args.embed:
        if not args.title:
            print("--title required with --embed", file=sys.stderr)
            sys.exit(2)
        in_path = args.in_path or args.body_file
        if not in_path:
            print("--in or body file required with --embed", file=sys.stderr)
            sys.exit(2)
        body = Path(in_path).read_text(encoding="utf-8")
        enriched = embed_task_yaml_block(body, title=args.title, feature_slug=args.feature_slug)
        if args.out_path:
            Path(args.out_path).write_text(enriched, encoding="utf-8")
        else:
            sys.stdout.write(enriched)
        sys.exit(0)

    if args.body_file:
        body = Path(args.body_file).read_text(encoding="utf-8")
    else:
        body = sys.stdin.read()

    meta = resolve_task_meta(body, title=args.title, feature_slug=args.feature_slug)
    print("null" if meta is None else json.dumps(meta))
    sys.exit(0)


if __name__ == "__main__":
    main()
