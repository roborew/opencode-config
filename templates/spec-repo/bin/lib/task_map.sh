#!/usr/bin/env bash
# Portable task_id -> issue number map (bash 3.2+; no declare -A).
set -euo pipefail

task_map_init() {
  TASK_MAP_FILE=$(mktemp) || { echo "ERROR: mktemp failed for task map" >&2; return 1; }
  : >"$TASK_MAP_FILE"
}

task_map_set() {
  printf '%s\t%s\n' "$1" "$2" >>"$TASK_MAP_FILE"
}

task_map_get() {
  awk -F'\t' -v id="$1" '$1==id {print $2; exit}' "$TASK_MAP_FILE"
}

task_map_cleanup() {
  rm -f "${TASK_MAP_FILE:-}"
}
