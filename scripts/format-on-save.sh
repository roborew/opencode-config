#!/usr/bin/env bash
# Format a single file after edit (manual or hook). Pass file path as $1.

set -euo pipefail
FILE_PATH="${1:-}"
[[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]] && exit 0

# shellcheck source=lib/shared.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/shared.sh"

ROOT=$(find_project_root "$(dirname "$FILE_PATH")")
EXT="${FILE_PATH##*.}"

# Biome
if [[ -f "$ROOT/node_modules/.bin/biome" ]] && { [[ -f "$ROOT/biome.json" ]] || [[ -f "$ROOT/biome.jsonc" ]]; }; then
  case "$EXT" in
    js|jsx|ts|tsx|json|css) "$ROOT/node_modules/.bin/biome" format --write "$FILE_PATH" 2>/dev/null && exit 0 ;;
  esac
fi

# Prettier
if [[ -f "$ROOT/node_modules/.bin/prettier" ]]; then
  case "$EXT" in
    js|jsx|ts|tsx|json|css|scss|md|yaml|yml|html)
      npx prettier --write "$FILE_PATH" 2>/dev/null && exit 0
      ;;
  esac
fi

# Ruff
if command -v ruff >/dev/null 2>&1 && [[ "$EXT" == "py" ]]; then
  if [[ -f "$ROOT/ruff.toml" || -f "$ROOT/.ruff.toml" ]] || grep -q '\[tool\.ruff\]' "$ROOT/pyproject.toml" 2>/dev/null; then
    ruff format "$FILE_PATH" 2>/dev/null || true
    ruff check --fix "$FILE_PATH" 2>/dev/null || true
    exit 0
  fi
fi

exit 0
