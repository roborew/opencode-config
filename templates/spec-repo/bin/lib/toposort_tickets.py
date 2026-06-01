#!/usr/bin/env python3
"""Topological sort of PRD tickets by depends_on (task ids). Print one id per line."""
import json
import sys


def main() -> None:
    data = json.load(sys.stdin)
    if not isinstance(data, list):
        print("tickets must be a JSON array", file=sys.stderr)
        sys.exit(1)
    ids = {t["id"]: t for t in data if "id" in t}
    order: list[str] = []
    remaining = set(ids)
    while remaining:
        progressed = False
        for tid in list(remaining):
            deps = set(ids[tid].get("depends_on") or [])
            unknown = deps - set(ids)
            if unknown:
                print(f"unknown depends_on for {tid}: {unknown}", file=sys.stderr)
                sys.exit(2)
            if deps.issubset(set(order)):
                order.append(tid)
                remaining.remove(tid)
                progressed = True
        if not progressed:
            print("cycle or unsatisfiable depends_on in tickets", file=sys.stderr)
            sys.exit(3)
    print("\n".join(order))


if __name__ == "__main__":
    main()
