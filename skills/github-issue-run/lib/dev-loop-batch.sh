#!/usr/bin/env bash
# Emit a JSON array of all currently runnable OpenCode child issues for feature:<slug>
# in one call (DAG-respecting). Returns every open issue carrying both
# `feature:<slug>` AND `state:ready-for-agent` whose `Blocked by:` dependencies are
# all CLOSED. Output shape: `[{number, title, body, opencode_meta, repo}, ...]`.
# Exit 1 with empty output when there is nothing runnable.
# Usage: dev-loop-batch.sh <feature_slug_without_prefix> [--repo OWNER/REPO]
set -euo pipefail
SLUG="${1:?feature slug required}"
shift || true
REPO="${GH_REPO:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="${2:?}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done
[[ -n "$REPO" ]] || REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
FEAT="feature:${SLUG}"
OC="${OPENCODE_CONFIG:-$HOME/.config/opencode}"
PARSE_META="${OC}/templates/spec-repo/bin/lib/extract_task_meta.py"

is_blocked_open() {
  local body="$1"
  local block_section deps
  block_section=$(printf '%s' "$body" | awk '/^## Blocked by$/{found=1; next} found && /^## /{exit} found{print}' || true)
  if [[ -z "$block_section" ]]; then
    local line
    line=$(printf '%s' "$body" | grep '^\*\*Blocked by:\*\*' | head -1 || true)
    block_section="$line"
  fi
  [[ -n "$block_section" ]] || return 1
  if printf '%s' "$block_section" | grep -qiE '\bnone\b|\(none\)'; then
    return 1
  fi
  deps=$(printf '%s' "$block_section" | grep -oE '#[0-9]+' | tr -d '#' || true)
  [[ -n "$deps" ]] || return 1
  local d st
  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    st=$(gh issue view "$d" --repo "$REPO" --json state -q .state 2>/dev/null || echo OPEN)
    if [[ "$st" != "CLOSED" ]]; then
      return 0
    fi
  done <<< "$(printf '%s\n' $deps)"
  return 1
}

extract_meta() {
  local body="$1" title="$2"
  if [[ -f "$PARSE_META" ]]; then
    local out
    out=$(printf '%s' "$body" | python3 "$PARSE_META" --title "$title" --feature-slug "$SLUG" 2>/dev/null || true)
    [[ -n "$out" ]] || out=null
    echo "$out"
  else
    printf '%s' "$body" | sed -n '/```opencode-task-yaml/,/```/p' | sed '1d;$d' | jq -c . 2>/dev/null || echo null
  fi
}

STUBS_FILE=$(mktemp)
trap 'rm -f "$STUBS_FILE"' EXIT
gh issue list --repo "$REPO" -L 200 --label "$FEAT" --label state:ready-for-agent --state open \
  --json number,title 2>/dev/null | jq -c 'sort_by(.number) | .[]' >"$STUBS_FILE" || true

if [[ ! -s "$STUBS_FILE" ]]; then
  exit 1
fi

OUT='[]'
while IFS= read -r stub; do
  [[ -n "$stub" ]] || continue
  number=$(printf '%s' "$stub" | jq -r .number)
  title=$(printf '%s' "$stub" | jq -r .title)
  row=$(gh issue view "$number" --repo "$REPO" --json number,title,body 2>/dev/null || true)
  [[ -n "$row" ]] || continue
  body=$(printf '%s' "$row" | jq -r .body)
  if is_blocked_open "$body"; then
    continue
  fi
  meta=$(extract_meta "$body" "$title")
  entry=$(printf '%s' "$row" | jq -c --argjson meta "${meta}" --arg rep "$REPO" \
    '{number: .number, title: .title, body: .body, opencode_meta: $meta, repo: $rep}')
  OUT=$(jq -c --argjson e "$entry" '. + [$e]' <<<"$OUT")
done <"$STUBS_FILE"

count=$(jq 'length' <<<"$OUT")
if [[ "$count" -eq 0 ]]; then
  exit 1
fi
printf '%s\n' "$OUT"