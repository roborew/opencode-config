#!/usr/bin/env bash
# Wrapper for existing_issue.py (fanout dedup).

existing_issue_number() {
  local repo="$1" title="$2" task_id="${3:-}"
  local script="${BIN_DIR}/lib/existing_issue.py"
  [[ -f "$script" ]] || { echo "missing $script" >&2; exit 8; }
  python3 "$script" "$repo" "$SLUG" "$title" "$task_id"
}

existing_issue_numbers() {
  local repo="$1" title="$2" task_id="${3:-}"
  local script="${BIN_DIR}/lib/existing_issue.py"
  [[ -f "$script" ]] || { echo "missing $script" >&2; exit 8; }
  python3 "$script" find-all "$repo" "$SLUG" "$title" "$task_id"
}
