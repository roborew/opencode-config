#!/usr/bin/env bash
# Swap exactly one state:* label on a GitHub issue (requires gh).
# Usage: issue-state-transition.sh <repo> <issue_number> <new_state_label>
# When transitioning to state:in-progress, verifies checkout contract if set:
#   OPENCODE_EXPECT_REPO_ROOT, OPENCODE_EXPECT_BRANCH
set -euo pipefail
REPO="${1:?repo owner/name}"
NUM="${2:?issue number}"
NEW="${3:?new state label e.g. state:in-progress}"

OC="${OPENCODE_CONFIG:-$HOME/.config/opencode}"
CONTRACT_SH="$OC/skills/github-issue-run/lib/checkout-contract.sh"

if [[ "$NEW" == "state:in-progress" && -n "${OPENCODE_EXPECT_REPO_ROOT:-}" && -n "${OPENCODE_EXPECT_BRANCH:-}" ]]; then
  if [[ -x "$CONTRACT_SH" ]] || [[ -f "$CONTRACT_SH" ]]; then
    bash "$CONTRACT_SH" --verify
  fi
fi

# Verifier gate backstop: state:ready-for-review requires a verifier_gate comment
# with all_stages: true and verdict: APPROVED AND the `verified` label. Without
# them, the issue cannot be marked ready-for-review (the orchestrator must run the
# verifier first). The `verified` label alone unlocks nothing — both are required.
if [[ "$NEW" == "state:ready-for-review" ]]; then
  COMMENTS=$(gh issue view "$NUM" --repo "$REPO" --comments --json comments -q '.comments[].body' 2>/dev/null || true)
  LABELS=$(gh issue view "$NUM" --repo "$REPO" --json labels -q '.labels[].name' 2>/dev/null || true)
  if ! grep -q 'verifier_gate:' <<<"$COMMENTS" \
     || ! grep -q 'all_stages: true' <<<"$COMMENTS" \
     || ! grep -q 'verdict: APPROVED' <<<"$COMMENTS" \
     || ! grep -qx 'verified' <<<"$LABELS"; then
    echo "BLOCKED: $REPO#$NUM -> state:ready-for-review requires a verifier_gate comment with all_stages: true and verdict: APPROVED AND the 'verified' label. Run the verifier and post the gate comment (which sets the label) first." >&2
    exit 1
  fi
fi

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

# Re-work re-arms verification: entering state:in-progress removes `verified` and
# re-adds `unverified`, so any re-implementation forces re-verification.
if [[ "$NEW" == "state:in-progress" ]]; then
  gh issue edit "$NUM" --repo "$REPO" --remove-label "verified" --add-label "unverified" 2>/dev/null || true
fi

echo "OK: $REPO#$NUM -> $NEW"
