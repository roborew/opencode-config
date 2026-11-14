#!/usr/bin/env python3
"""Emit opencode-task-yaml text for a fanout ticket (routing metadata only)."""
from __future__ import annotations

import json
import sys

try:
    import yaml  # type: ignore
except ImportError:
    yaml = None


def main() -> None:
    if yaml is None:
        print("PyYAML required", file=sys.stderr)
        sys.exit(4)
    meta = json.load(sys.stdin)
    if not isinstance(meta, dict):
        print("meta must be a JSON object", file=sys.stderr)
        sys.exit(1)
    allowed = ("task_id", "owner", "capability", "depends_on", "design_delivery", "stages")
    slim = {k: meta[k] for k in allowed if k in meta and meta[k] is not None}
    if "depends_on" not in slim:
        slim["depends_on"] = []
    print(yaml.dump(slim, default_flow_style=False, sort_keys=False).rstrip())


if __name__ == "__main__":
    main()
