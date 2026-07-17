#!/usr/bin/env bash
# Merge a feature PR and delete the head branch when safe.
# Usage: merge-feature-prs.sh --repo OWNER/NAME --pr NUMBER [--merge-method merge|squash|rebase]
set -euo pipefail

REPO=""
PR_NUM=""
MERGE_METHOD="merge"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="${2:?}"
      shift 2
      ;;
    --pr)
      PR_NUM="${2:?}"
      shift 2
      ;;
    --merge-method)
      MERGE_METHOD="${2:?}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

[[ -n "$REPO" ]] || { echo "--repo required" >&2; exit 2; }
[[ -n "$PR_NUM" ]] || { echo "--pr required" >&2; exit 2; }

PROTECTED_RE='^(develop|main|master)$'

pr_json="$(gh pr view "$PR_NUM" --repo "$REPO" --json headRefName,baseRefName,state,mergeable,url)"
head="$(echo "$pr_json" | jq -r '.headRefName')"
base="$(echo "$pr_json" | jq -r '.baseRefName')"
state="$(echo "$pr_json" | jq -r '.state')"
url="$(echo "$pr_json" | jq -r '.url')"

if [[ "$state" != "OPEN" ]]; then
  echo "SKIP: PR already ${state}: ${url}"
  exit 0
fi

case "$MERGE_METHOD" in
  merge) merge_flag=(--merge) ;;
  squash) merge_flag=(--squash) ;;
  rebase) merge_flag=(--rebase) ;;
  *)
    echo "invalid --merge-method: $MERGE_METHOD" >&2
    exit 2
    ;;
esac

gh pr merge "$PR_NUM" --repo "$REPO" "${merge_flag[@]}"
echo "MERGED: ${url}"

if [[ "$head" =~ $PROTECTED_RE ]]; then
  echo "SKIP_BRANCH_DELETE: protected head branch ${head}"
  exit 0
fi

if gh api "repos/${REPO}/git/refs/heads/${head}" >/dev/null 2>&1; then
  gh api -X DELETE "repos/${REPO}/git/refs/heads/${head}" >/dev/null
  echo "DELETED_BRANCH: ${head}"
else
  echo "SKIP_BRANCH_DELETE: branch ${head} not found (may already be deleted)"
fi
