#!/usr/bin/env bash
# Close all open feature:<slug> issues in an impl repo at Spec merge ceremony.
# Usage: close-feature-issues.sh <kebab-slug> <pr_url> [--repo OWNER/NAME]
set -euo pipefail

SLUG="${1:?kebab slug required}"
PR_URL="${2:?pr url required}"
shift 2 || true
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

LABEL="feature:${SLUG}"
COMMENT="Spec feature-complete: merged. PR: ${PR_URL}"

if [[ -z "$REPO" ]]; then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
fi
if [[ -z "$REPO" ]]; then
  echo "ERROR: could not resolve repo (pass --repo OWNER/NAME)" >&2
  exit 1
fi

owner="${REPO%%/*}"
name="${REPO##*/}"
label_q="$(printf '%s' "$LABEL" | jq -sRr @uri)"
if ! issues_json="$(gh api "repos/${owner}/${name}/issues?labels=${label_q}&state=open" \
  --paginate \
  --jq '[.[] | select(has("pull_request") | not) | {number, labels}]')"; then
  issues_json='[]'
fi

closed=0
while IFS= read -r num; do
  [[ -z "$num" ]] && continue
  gh issue close "$num" --repo "$REPO" --comment "$COMMENT"
  echo "CLOSED: ${REPO}#${num}"
  closed=$((closed + 1))
done < <(echo "$issues_json" | jq -r '.[].number')

echo "SUMMARY: closed=${closed} repo=${REPO} label=${LABEL}"
