#!/usr/bin/env bash
# Emit a compact JSON array of all currently runnable OpenCode child issues for feature:<slug>
# in a single gh API call (DAG-respecting). A ticket is runnable when it is OPEN, carries both
# `feature:<slug>` AND `state:ready-for-agent`, and every `Blocked by:` dependency is CLOSED.
#
# Output shape: [{number, title, url, repo}, ...] — one compact line, sorted by number.
# Deliberately relay-safe: entries NEVER carry issue bodies or opencode-task-yaml meta.
# The developer Task that runs this script relays stdout verbatim; bodies are fetched only to
# parse `Blocked by:` and are never emitted. Coder sessions reconstruct full ticket context
# from GitHub (ticket-lifecycle §0) and worktree-manager derives <abbrev> from the title itself.
#
# Exit codes: 0 = runnable batch on stdout; 1 = nothing runnable (batch loop done);
#             2 = gh/API failure — surface verbatim, never treat as "all done".
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

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
ISSUES_FILE="$WORK/issues.json"
CANDS_FILE="$WORK/candidates.ndjson"
STATES_FILE="$WORK/states.json"

# One gh call: OPEN and CLOSED feature issues. Closed siblings resolve `Blocked by:` deps
# locally (fanout deps are same-feature tickets). -L caps the combined result; 200 covers
# any realistic fanout.
if ! gh issue list --repo "$REPO" -L 200 --state all --label "$FEAT" \
  --json number,title,url,state,labels,body >"$ISSUES_FILE" 2>"$WORK/gh.err"; then
  echo "dev-loop-batch: gh issue list failed for ${REPO} label ${FEAT}" >&2
  cat "$WORK/gh.err" >&2
  exit 2
fi

# number -> state map for local dep resolution.
jq -c 'map({key: (.number | tostring), value: .state}) | from_entries' "$ISSUES_FILE" >"$STATES_FILE"

# Candidates: OPEN + state:ready-for-agent, sorted by number.
jq -c 'sort_by(.number)
  | .[]
  | select(.state == "OPEN")
  | select(any(.labels[]?; .name == "state:ready-for-agent"))
  | {number, title, url, body}' "$ISSUES_FILE" >"$CANDS_FILE" || true

blocked_by_section() {
  local body="$1" section
  section=$(printf '%s' "$body" | awk '/^## Blocked by$/{found=1; next} found && /^## /{exit} found{print}' || true)
  if [[ -z "$section" ]]; then
    section=$(printf '%s' "$body" | grep '^\*\*Blocked by:\*\*' | head -1 || true)
  fi
  printf '%s' "$section"
}

# 0 = every dependency CLOSED (or no dependencies); 1 = at least one dep not CLOSED.
all_deps_closed() {
  local body="$1" section deps d st
  section=$(blocked_by_section "$body")
  [[ -n "$section" ]] || return 0
  if printf '%s' "$section" | grep -qiE '\bnone\b|\(none\)'; then
    return 0
  fi
  deps=$(printf '%s' "$section" | grep -oE '#[0-9]+' | tr -d '#' || true)
  [[ -n "$deps" ]] || return 0
  for d in $deps; do
    st=$(jq -r --arg k "$d" '.[$k] // ""' "$STATES_FILE")
    if [[ -z "$st" ]]; then
      # Not in this feature's issue set (rare: cross-feature ref) — single fallback lookup.
      st=$(gh issue view "$d" --repo "$REPO" --json state -q .state 2>/dev/null || echo OPEN)
    fi
    [[ "$st" == "CLOSED" ]] || return 1
  done
  return 0
}

OUT='[]'
while IFS= read -r cand; do
  [[ -n "$cand" ]] || continue
  number=$(printf '%s' "$cand" | jq -r .number)
  title=$(printf '%s' "$cand" | jq -r .title)
  url=$(printf '%s' "$cand" | jq -r .url)
  body=$(printf '%s' "$cand" | jq -r .body)
  if ! all_deps_closed "$body"; then
    continue
  fi
  entry=$(jq -c -n --argjson n "$number" --arg t "$title" --arg u "$url" --arg r "$REPO" \
    '{number: $n, title: $t, url: $u, repo: $r}')
  OUT=$(jq -c --argjson e "$entry" '. + [$e]' <<<"$OUT")
done <"$CANDS_FILE"

count=$(jq 'length' <<<"$OUT")
if [[ "$count" -eq 0 ]]; then
  exit 1
fi
printf '%s\n' "$OUT"
