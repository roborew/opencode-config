#!/usr/bin/env bash
# Run the best-matching test for a source file. Usage: auto-test.sh path/to/file.py|ts|tsx

set -euo pipefail
SRC="${1:-}"
[[ -z "$SRC" || ! -f "$SRC" ]] && exit 0

find_root() {
  local dir
  dir=$(cd "$(dirname "$SRC")" && pwd)
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/package.json" || -f "$dir/pyproject.toml" || -d "$dir/.git" ]]; then
      echo "$dir"
      return
    fi
    dir=$(dirname "$dir")
  done
  echo "$(cd "$(dirname "$SRC")" && pwd)"
}

ROOT=$(find_root)
BASE=$(basename "$SRC")
NAME="${BASE%.*}"
EXT="${SRC##*.}"

cd "$ROOT"

if [[ "$EXT" == "py" ]]; then
  if command -v pytest >/dev/null 2>&1; then
    for candidate in "tests/test_${NAME}.py" "test_${NAME}.py" "${NAME}_test.py" "tests/${NAME}_test.py"; do
      if [[ -f "$candidate" ]]; then
        pytest -q "$candidate" && exit 0
      fi
    done
  fi
fi

if [[ "$EXT" =~ ^(ts|tsx|js|jsx)$ ]]; then
  if [[ -f "$ROOT/package.json" ]]; then
    for candidate in "${NAME}.test.${EXT}" "${NAME}.spec.${EXT}" "__tests__/${NAME}.test.${EXT}"; do
      if [[ -f "$candidate" ]]; then
        if grep -q '"vitest"' "$ROOT/package.json" 2>/dev/null && command -v npx >/dev/null 2>&1; then
          npx vitest run "$candidate" 2>/dev/null && exit 0
        fi
        if grep -q '"jest"' "$ROOT/package.json" 2>/dev/null && command -v npx >/dev/null 2>&1; then
          npx jest "$candidate" 2>/dev/null && exit 0
        fi
      fi
    done
  fi
fi

exit 0
