#!/usr/bin/env python3
"""Read and update PRD markdown frontmatter (YAML between --- delimiters)."""
from __future__ import annotations

import json
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


def split_prd(text: str) -> tuple[str, str, str]:
    if not text.startswith("---"):
        raise ValueError("PRD must start with --- frontmatter delimiter")
    end = text.index("---", 3)
    front = text[3:end]
    body = text[end + 3 :]
    if body.startswith("\n"):
        body = body[1:]
    return text[: end + 3], front, body


def load_prd(path: Path) -> dict:
    if yaml is None:
        raise RuntimeError("PyYAML required")
    text = path.read_text(encoding="utf-8")
    block = extract_frontmatter(text)
    data = yaml.safe_load(block) or {}
    if not isinstance(data, dict):
        raise ValueError("PRD frontmatter must be a YAML mapping")
    return data


def set_frontmatter_field(path: Path, field: str, value: str) -> None:
    if yaml is None:
        raise RuntimeError("PyYAML required")
    text = path.read_text(encoding="utf-8")
    _, front, body = split_prd(text)
    data = yaml.safe_load(front) or {}
    if not isinstance(data, dict):
        raise ValueError("PRD frontmatter must be a YAML mapping")
    data[field] = value
    dumped = yaml.safe_dump(
        data,
        default_flow_style=False,
        sort_keys=False,
        allow_unicode=True,
    ).rstrip("\n")
    path.write_text(f"---\n{dumped}\n---\n{body}", encoding="utf-8")


def main() -> None:
    if len(sys.argv) < 3:
        print(
            "usage: prd_io.py <command> <prd.md> [args]\n"
            "  commands: tickets_json, tickets_count, get <field>, set <field> <value>, slices_json",
            file=sys.stderr,
        )
        sys.exit(1)

    cmd = sys.argv[1]
    path = Path(sys.argv[2])

    if cmd == "set":
        if len(sys.argv) < 5:
            print("usage: prd_io.py set <prd.md> <field> <value>", file=sys.stderr)
            sys.exit(1)
        field = sys.argv[3]
        value = sys.argv[4]
        if not path.is_file():
            print(f"missing: {path}", file=sys.stderr)
            sys.exit(2)
        try:
            set_frontmatter_field(path, field, value)
        except (ValueError, RuntimeError) as e:
            print(str(e), file=sys.stderr)
            sys.exit(3)
        return

    if not path.is_file():
        print(f"missing: {path}", file=sys.stderr)
        sys.exit(2)

    try:
        data = load_prd(path)
    except (ValueError, RuntimeError) as e:
        print(str(e), file=sys.stderr)
        sys.exit(3)

    if cmd == "tickets_json":
        print(json.dumps(data.get("tickets") or []))
    elif cmd == "tickets_count":
        tickets = data.get("tickets") or []
        print(len(tickets) if isinstance(tickets, list) else 0)
    elif cmd == "get":
        field = sys.argv[3] if len(sys.argv) > 3 else ""
        if not field:
            print("usage: prd_io.py get <prd.md> <field>", file=sys.stderr)
            sys.exit(1)
        print(data.get(field) or "")
    elif cmd == "slices_json":
        print(json.dumps(data.get("slices") or {}))
    else:
        print(f"unknown command: {cmd}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
