#!/usr/bin/env bash
# PR stabilization helper for the ticket session under `github_issue_full`.
# Emits JSON classification of CI state and review comments for a sub-PR, plus
# runs one bounded `gh pr checks --watch` so the ticket session can iterate
# fix-now items without writing the same prose in `ticket-lifecycle`.
#
# Output shape (stdout, single JSON object):
#   {
#     "pr_url":  "<url>",
#     "pr_number": <int>,
#     "repo":  "OWNER/REPO",
#     "branch":"opencode/ticket-<n>-<slug>-<abbrev>",
#     "base":  "opencode/feat-<slug>",
#     "ci":    {"state":"pass|fail|pending","checks":[...],"timeout":false},
#     "comments":     [{"author","body","classification":"fix-now|defer|awaiting-human"}],
#     "reviews":      [...],
#     "mergeable":    "MERGEABLE|CONFLICTING|UNKNOWN",
#     "classify":     "ready|fix-now|awaiting-human",
#     "evidence":     "<one-line summary>"
#   }
#
# Usage:
#   pr-stabilize-watch.sh <pr_url> [--timeout SECONDS]
#
# Env:
#   OC_CI_WAIT_TIMEOUT  default 1800 (30 min); bound on `gh pr checks --watch`.
#
# The script is read-only against the repo (no pushes, no comments posted). The
# ticket session handles fix-now code changes in-worktree and pushes them itself.
set -euo pipefail
PR_URL="${1:?pr_url required}"
shift || true
TIMEOUT="${OC_CI_WAIT_TIMEOUT:-1800}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout)
      TIMEOUT="${2:?}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

REPO=$(gh pr view "$PR_URL" --json url -q '.url' >/dev/null 2>&1 && true; gh repo view --json nameWithOwner -q .nameWithOwner)
PR_JSON=$(gh pr view "$PR_URL" --repo "$REPO" --json number,title,headRefName,baseRefName,mergeable,statusCheckRollup,comments,reviews 2>/dev/null || echo '{}')

PR_NUMBER=$(printf '%s' "$PR_JSON" | jq -r '.number // empty')
BRANCH=$(printf '%s' "$PR_JSON" | jq -r '.headRefName // empty')
BASE=$(printf '%s' "$PR_JSON" | jq -r '.baseRefName // empty')
MERGEABLE=$(printf '%s' "$PR_JSON" | jq -r '.mergeable // "UNKNOWN"')

# Bounded CI watch. gh pr checks --watch blocks until checks complete or timeout.
WATCH_JSON=$(gh pr checks "$PR_URL" --repo "$REPO" --watch --timeout "$TIMEOUT" --json name,state,conclusion 2>/dev/null || echo '[]')
CI_STATE="pass"
if [[ "$(jq 'length' <<<"$WATCH_JSON")" -eq 0 ]]; then
  CI_STATE="pending"
else
  fails=$(jq '[.[] | select(.conclusion=="FAILURE" or .conclusion=="ERROR" or .conclusion=="CANCELLED")] | length' <<<"$WATCH_JSON")
  pendings=$(jq '[.[] | select(.state=="pending" or .conclusion==null)] | length' <<<"$WATCH_JSON")
  if [[ "$fails" -gt 0 ]]; then
    CI_STATE="fail"
  elif [[ "$pendings" -gt 0 ]]; then
    CI_STATE="pending"
  fi
fi

CLASSIFY_COMMENTS=$(printf '%s' "$PR_JSON" | jq -c '
  (.comments // []) | map({
    author:  (.author.login // "unknown"),
    body:    (.body // ""),
    classification: (
      if (.body | test("(?i)\\b(wip|do not merge|do-not-merge|hold)\\b")) then "awaiting-human"
      elif (.body | test("(?i)\\b(security|vulnerability|sql injection|xss|csrf|rce)\\b")) then "fix-now"
      elif (.body | test("(?i)\\b(typo|nit:|nitpick|optional|suggestion|fyi)\\b")) then "defer"
      else "fix-now"
      end
    )
  })
')

CLASSIFY_REVIEWS=$(printf '%s' "$PR_JSON" | jq -c '
  (.reviews // []) | map({
    author: (.author.login // "unknown"),
    state:  (.state // "PENDING"),
    body:   (.body // ""),
    classification: (
      if (.body | test("(?i)\\b(nit:|nitpick|optional)\\b")) then "defer"
      else "fix-now"
      end
    )
  })
')

FIX_NOW=$(jq '[.[] | select(.classification=="fix-now")] | length' <<<"$CLASSIFY_COMMENTS")
AWAIT=$(jq '[.[] | select(.classification=="awaiting-human")] | length' <<<"$CLASSIFY_COMMENTS")
EVIDENCE="ci=$CI_STATE fix_now=$FIX_NOW awaiting_human=$AWAIT mergeable=$MERGEABLE"

if [[ "$CI_STATE" == "fail" || "$FIX_NOW" -gt 0 || "$MERGEABLE" == "CONFLICTING" ]]; then
  CLASS="fix-now"
elif [[ "$AWAIT" -gt 0 || "$CI_STATE" == "pending" ]]; then
  CLASS="awaiting-human"
else
  CLASS="ready"
fi

jq -nc \
  --arg pr_url "$PR_URL" \
  --argjson pr_number "${PR_NUMBER:-null}" \
  --arg repo "$REPO" \
  --arg branch "$BRANCH" \
  --arg base "$BASE" \
  --arg mergeable "$MERGEABLE" \
  --argjson ci_state "$([ "$CI_STATE" = "pass" ] && echo '"pass"' || ([ "$CI_STATE" = "fail" ] && echo '"fail"' || echo '"pending"'))" \
  --argjson checks "$WATCH_JSON" \
  --argjson comments "$CLASSIFY_COMMENTS" \
  --argjson reviews "$CLASSIFY_REVIEWS" \
  --arg classify "$CLASS" \
  --arg evidence "$EVIDENCE" \
  '{
    pr_url:    $pr_url,
    pr_number: $pr_number,
    repo:      $repo,
    branch:    $branch,
    base:      $base,
    mergeable: $mergeable,
    ci:        { state: $ci_state, checks: $checks, timeout: false },
    comments:  $comments,
    reviews:   $reviews,
    classify:  $classify,
    evidence:  $evidence
  }'