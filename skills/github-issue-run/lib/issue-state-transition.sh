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
  # Label may not be present; ignore "not found" but warn on other errors.
  if ! gh issue edit "$NUM" --repo "$REPO" --remove-label "$l" 2>/dev/null; then
    if gh issue view "$NUM" --repo "$REPO" --json labels -q '[.labels[].name] | join(",")' 2>/dev/null | grep -q "$l"; then
      echo "WARN: failed to remove label $l from $REPO#$NUM" >&2
    fi
  fi
done
if ! gh issue edit "$NUM" --repo "$REPO" --add-label "$NEW"; then
  echo "ERROR: failed to add label $NEW to $REPO#$NUM" >&2
  exit 1
fi
echo "OK: $REPO#$NUM -> $NEW"
