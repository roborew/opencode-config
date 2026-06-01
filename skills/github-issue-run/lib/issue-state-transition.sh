#!/usr/bin/env bash
# Swap exactly one state:* label on a GitHub issue (requires gh).
# Usage: issue-state-transition.sh <repo> <issue_number> <new_state_label>
set -euo pipefail
REPO="${1:?repo owner/name}"
NUM="${2:?issue number}"
NEW="${3:?new state label e.g. state:in-progress}"

STATE_LABELS=(
  state:needs-triage
  state:needs-info
  state:ready-for-agent
  state:in-progress
  state:ready-for-review
  state:blocked
  state:done
  state:ready-for-human
  state:wontfix
)

for l in "${STATE_LABELS[@]}"; do
  gh issue edit "$NUM" --repo "$REPO" --remove-label "$l" 2>/dev/null || true
done
gh issue edit "$NUM" --repo "$REPO" --add-label "$NEW"
echo "OK: $REPO#$NUM -> $NEW"
