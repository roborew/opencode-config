#!/usr/bin/env bash
# Swap exactly one state:* label on a GitHub issue (requires gh).
# Usage: issue-state-transition.sh <repo> <issue_number> <new_state_label>
set -euo pipefail
REPO="${1:?repo owner/name}"
NUM="${2:?issue number}"
NEW="${3:?new state label e.g. state:in-progress}"

OC="${OPENCODE_CONFIG:-$HOME/.config/opencode}"
# shellcheck source=../../../scripts/lib/shared.sh
source "${OC}/scripts/lib/shared.sh"

transition_issue_state "$REPO" "$NUM" "$NEW"
echo "OK: $REPO#$NUM -> $NEW"
