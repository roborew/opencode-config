#!/usr/bin/env bash
# Prints git / PR context for pasting into a session. Run from repo root.

set -euo pipefail

CONTEXT=""

BRANCH=$(git branch --show-current 2>/dev/null || true)
if [[ -n "$BRANCH" ]]; then
  CONTEXT="Branch: $BRANCH"
elif git rev-parse --git-dir >/dev/null 2>&1; then
  SHORT_SHA=$(git rev-parse --short HEAD 2>/dev/null || true)
  CONTEXT="HEAD: detached at ${SHORT_SHA:-unknown}"
fi

LAST_COMMIT=$(git log --oneline -1 2>/dev/null || true)
[[ -n "$LAST_COMMIT" ]] && CONTEXT="$CONTEXT | Last commit: $LAST_COMMIT"

CHANGES=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
if [[ "${CHANGES:-0}" -gt 0 ]]; then
  CONTEXT="$CONTEXT | Uncommitted changes: $CHANGES files"
fi

if ! git diff --cached --quiet 2>/dev/null; then
  CONTEXT="$CONTEXT | Staged: yes"
fi

STASH_COUNT=$(git stash list 2>/dev/null | wc -l | tr -d ' ')
if [[ "${STASH_COUNT:-0}" -gt 0 ]]; then
  CONTEXT="$CONTEXT | Stashes: $STASH_COUNT"
fi

if command -v gh >/dev/null 2>&1; then
  PR_INFO=$(gh pr view --json number,title,state --jq '"PR #\(.number): \(.title) (\(.state))"' 2>/dev/null || true)
  [[ -n "$PR_INFO" ]] && CONTEXT="$CONTEXT | $PR_INFO"
fi

[[ -n "$CONTEXT" ]] && echo "$CONTEXT"
exit 0
