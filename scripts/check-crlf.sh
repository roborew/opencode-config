#!/usr/bin/env bash
# Fail if any tracked text file under bin/, scripts/, or templates/ uses CRLF.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

paths=(bin scripts templates .gitattributes)

bad=()
for base in "${paths[@]}"; do
  [[ -e "$base" ]] || continue
  while IFS= read -r -d '' f; do
    [[ -f "$f" ]] || continue
    if grep -q $'\r' "$f" 2>/dev/null; then
      bad+=("$f")
    fi
  done < <(find "$base" -type f ! -path '*/__pycache__/*' ! -name '*.pyc' -print0 2>/dev/null)
done

if ((${#bad[@]} > 0)); then
  echo "ERROR: CRLF line endings (use LF for shell scripts and tooling):" >&2
  printf '  %s\n' "${bad[@]}" >&2
  echo "Fix: python3 scripts/normalize-line-endings.py" >&2
  exit 1
fi

echo "check-crlf: ok"
