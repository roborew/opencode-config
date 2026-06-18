#!/usr/bin/env bash
# Emit JSON for the next runnable OpenCode child issue in the current repo, or nothing.
# Runnable = open, has state:ready-for-agent + feature:<slug>, and every **Blocked by:** #n is CLOSED.
# Usage: next-runnable-issue.sh <feature_slug_without_prefix>
set -euo pipefail
SLUG="${1:?feature slug required}"
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
FEAT="feature:${SLUG}"
OC="${OPENCODE_CONFIG:-$HOME/.config/opencode}"
PARSE_META="${OC}/templates/spec-repo/bin/lib/extract_task_meta.py"

RAW=$(gh issue list --repo "$REPO" -L 200 --label "$FEAT" --label state:ready-for-agent --state open --json number,title,body 2>/dev/null || true)
if [[ -z "$RAW" ]]; then
  echo "WARN: no issues returned for ${FEAT} state:ready-for-agent in ${REPO} (API error or none exist)" >&2
  exit 1
fi
LIST=$(echo "$RAW" | jq 'sort_by(.number)')
[[ "$LIST" != "[]" ]] || exit 1

is_blocked_open() {
  local body="$1"
  local line
  line=$(echo "$body" | grep '^\*\*Blocked by:\*\*' | head -1 || true)
  [[ -n "$line" ]] || return 1
  if echo "$line" | grep -q '(none)'; then
    return 1
  fi
  local deps
  deps=$(echo "$line" | grep -oE '#[0-9]+' | tr -d '#' || true)
  [[ -n "$deps" ]] || return 1
  local d st
  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    if ! st=$(gh issue view "$d" --repo "$REPO" --json state -q .state 2>/dev/null); then
      echo "WARN: could not fetch state of #$d; assuming OPEN (blocked)" >&2
      st="OPEN"
    fi
    if [[ "$st" != "CLOSED" ]]; then
      return 0
    fi
  done <<< "$(printf '%s\n' $deps)"
  return 1
}

extract_meta() {
  local body="$1"
  if [[ -f "$PARSE_META" ]]; then
    echo "$body" | python3 "$PARSE_META" 2>/dev/null || echo null
  else
    echo "$body" | sed -n '/```opencode-task-yaml/,/```/p;/```opencode-task-json/,/```/p' | sed '1d;$d' | jq -c . 2>/dev/null || echo null
  fi
}

while IFS= read -r row; do
  body=$(echo "$row" | jq -r .body)
  if is_blocked_open "$body"; then
    continue
  fi
  meta=$(extract_meta "$body")
  jq -nc --argjson row "$row" --argjson meta "${meta}" \
    --arg rep "$REPO" \
    '{number: $row.number, title: $row.title, body: $row.body, opencode_meta: $meta, repo: $rep}'
  exit 0
done < <(echo "$LIST" | jq -c '.[]')

exit 1
