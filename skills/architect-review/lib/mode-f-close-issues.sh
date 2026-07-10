#!/usr/bin/env bash
# Mode F sign-off: transition feature:<slug> issues to state:done and close them.
# Only closes issues that currently have state:ready-for-review.
# Usage: mode-f-close-issues.sh <kebab-slug> [pr_url_for_comment] [--repo OWNER/NAME]
set -euo pipefail

SLUG="${1:?kebab slug required}"
shift || true
PR_URL=""
REPO="${GH_REPO:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="${2:?}"
      shift 2
      ;;
    *)
      if [[ -z "$PR_URL" ]]; then
        PR_URL="$1"
        shift
      else
        echo "unknown argument: $1" >&2
        exit 2
      fi
      ;;
  esac
done

LABEL="feature:${SLUG}"

OC="${OPENCODE_CONFIG:-$HOME/.config/opencode}"
TRANSITION="${OC}/skills/github-issue-run/lib/issue-state-transition.sh"

if [[ ! -x "$TRANSITION" ]]; then
  echo "ERROR: missing issue-state-transition.sh at $TRANSITION" >&2
  exit 1
fi

if [[ -z "$REPO" ]]; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
fi
if [[ -z "$REPO" ]]; then
  echo "ERROR: could not resolve repo (pass --repo OWNER/NAME or run from impl repo with gh auth)" >&2
  exit 1
fi

COMMENT="Architect Mode F sign-off."
[[ -n "$PR_URL" ]] && COMMENT="${COMMENT} PR: ${PR_URL}"

owner="${REPO%%/*}"
name="${REPO##*/}"
# gh api -f on GET /issues is interpreted as POST body (422); use query string.
label_q="$(printf '%s' "$LABEL" | jq -sRr @uri)"
if ! issues_json="$(gh api "repos/${owner}/${name}/issues?labels=${label_q}&state=open" \
  --paginate \
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
