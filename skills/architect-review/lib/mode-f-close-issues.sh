#!/usr/bin/env bash
# Mode F sign-off: transition feature:<slug> issues to state:done and close them.
# Only closes issues that currently have state:ready-for-review.
# Usage: mode-f-close-issues.sh <kebab-slug> [pr_url_for_comment]
set -euo pipefail

SLUG="${1:?kebab slug required}"
PR_URL="${2:-}"
LABEL="feature:${SLUG}"

OC="${OPENCODE_CONFIG:-$HOME/.config/opencode}"
TRANSITION="${OC}/skills/github-issue-run/lib/issue-state-transition.sh"

if [[ ! -x "$TRANSITION" ]]; then
  echo "ERROR: missing issue-state-transition.sh at $TRANSITION" >&2
  exit 1
fi

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner || true)"
if [[ -z "$REPO" ]]; then
  echo "ERROR: could not resolve current repo (run from impl repo with gh auth)" >&2
  exit 1
fi

COMMENT="Architect Mode F sign-off."
[[ -n "$PR_URL" ]] && COMMENT="${COMMENT} PR: ${PR_URL}"

owner="${REPO%%/*}"
name="${REPO##*/}"
if ! issues_json="$(gh api "repos/${owner}/${name}/issues" \
  --paginate \
  -f labels="${LABEL}" \
  -f state=open \
  --jq '[.[] | select(has("pull_request") | not) | {number, labels}]')"; then
  issues_json='[]'
fi
count="$(echo "$issues_json" | jq 'length')"
if [[ "$count" -eq 0 ]]; then
  echo "OK: no open issues with label ${LABEL} in ${REPO}"
  exit 0
fi

closed=0
skipped=0

while IFS= read -r num; do
  [[ -z "$num" ]] && continue
  labels="$(echo "$issues_json" | jq -r --argjson n "$num" '.[] | select(.number == $n) | [.labels[].name] | join(",")')"
  if [[ "$labels" != *"state:ready-for-review"* ]]; then
    echo "SKIP: ${REPO}#${num} (not state:ready-for-review)" >&2
    skipped=$((skipped + 1))
    continue
  fi
  bash "$TRANSITION" "$REPO" "$num" "state:done"
  gh issue close "$num" --repo "$REPO" --comment "$COMMENT"
  echo "CLOSED: ${REPO}#${num}"
  closed=$((closed + 1))
done < <(echo "$issues_json" | jq -r '.[].number')

echo "SUMMARY: closed=${closed} skipped=${skipped} repo=${REPO} label=${LABEL}"
if [[ "$skipped" -gt 0 ]]; then
  exit 2
fi
