#!/usr/bin/env bash
# Swap exactly one state:* label on a GitHub issue (requires gh).
# Usage: issue-state-transition.sh <repo> <issue_number> <new_state_label>
# When transitioning to state:in-progress, verifies checkout contract if set:
#   OPENCODE_EXPECT_REPO_ROOT, OPENCODE_EXPECT_BRANCH
# Enforces the `verified`/`unverified` binary pair on every transition: after the
# new state label is applied, exactly one of the pair is left on the issue, with
# the rule below. The only writer of `verified` outside the gate-failed path is
# `scripts/issue-verified-transition.sh` (called by the coder on APPROVED).
set -euo pipefail
REPO="${1:?repo owner/name}"
NUM="${2:?issue number}"
NEW="${3:?new state label e.g. state:in-progress}"

OC="${OPENCODE_CONFIG:-$HOME/.config/opencode}"
CONTRACT_SH="$OC/scripts/checkout-contract.sh"

if [[ "$NEW" == "state:in-progress" && -n "${OPENCODE_EXPECT_REPO_ROOT:-}" && -n "${OPENCODE_EXPECT_BRANCH:-}" ]]; then
  if [[ -x "$CONTRACT_SH" ]] || [[ -f "$CONTRACT_SH" ]]; then
    bash "$CONTRACT_SH" --verify
  fi
fi

# Code-review gate backstop: state:ready-for-ticket-review requires a code_review_gate
# comment whose body contains EXACT field values (^code_review_gate:$, ^  all_stages: true$,
# ^  verdict: APPROVED$) AND whose author.login matches ${OPENCODE_CODER_AUTHOR} when set
# (default empty = no author check — preserves existing behavior on repos that have not
# configured the contract yet), AND the `verified` label. Without all three, the issue
# cannot be marked ready-for-ticket-review (the orchestrator must run code-review first).
# `verified` alone unlocks nothing — both comment and label are required.
#
# Record pass/fail into GATE_PASS so the post-transition swap can run either way
# (a BLOCKED transition still needs to strip any stale `verified`).
GATE_PASS=true
if [[ "$NEW" == "state:ready-for-ticket-review" ]]; then
  TRUSTED_AUTHOR="${OPENCODE_CODER_AUTHOR:-}"
  COMMENTS_JSON=$(gh issue view "$NUM" --repo "$REPO" --comments \
    --json comments -q '.comments[] | {body, author: .author.login}' 2>/dev/null || true)
  # Select the latest comment whose body matches the three exact field values
  # AND whose author matches the trusted identity (when configured). The
  # `select($author == "" or .author == $author)` line is the empty-config
  # short-circuit — when OPENCODE_CODER_AUTHOR is unset the author filter is
  # bypassed. When set, `.author == null` (deleted GitHub accounts) is
  # correctly rejected because null != <string>.
  MATCH=$(printf '%s\n' "$COMMENTS_JSON" | jq -s --arg author "$TRUSTED_AUTHOR" '
    [ .[] | .body as $b | .author as $a
      | select($b | test("(?m)^code_review_gate:"))
      | select($b | test("(?m)^  all_stages: true$"))
      | select($b | test("(?m)^  verdict: APPROVED$"))
      | select($author == "" or .author == $author)
    ] | last // empty')
  LABELS=$(gh issue view "$NUM" --repo "$REPO" --json labels -q '.labels[].name' 2>/dev/null || true)
  if [[ -z "$MATCH" ]] || ! grep -qx 'verified' <<<"$LABELS"; then
    echo "BLOCKED: $REPO#$NUM -> state:ready-for-ticket-review requires a code_review_gate comment with all_stages: true and verdict: APPROVED authored by ${TRUSTED_AUTHOR:-<any>} AND the 'verified' label. Run code-review and post the gate comment (which sets the label) first." >&2
    GATE_PASS=false
  fi
fi

# Outbound guard: state:ticket-reviewed requires `verified` to remain set. This
# catches the #247-class drift where a sub-PR is merged out-of-band (human merges
# via GitHub UI) and the develop orchestrator transitions to state:ticket-reviewed
# without the coder having ever posted the gate comment or stamped `verified`.
# Runs BEFORE the state-label swap so a BLOCKED here does not mutate labels.
if [[ "$NEW" == "state:ticket-reviewed" ]]; then
  LABELS_NOW=$(gh issue view "$NUM" --repo "$REPO" --json labels -q '.labels[].name' 2>/dev/null || true)
  if ! grep -qx 'verified' <<<"$LABELS_NOW"; then
    echo "BLOCKED: $REPO#$NUM -> state:ticket-reviewed requires the 'verified' label to remain set. The label was dropped between ready-for-ticket-review and review; investigate before re-running." >&2
    exit 1
  fi
fi

STATE_LABELS=(
  state:needs-triage
  state:needs-info
  state:ready-for-agent
  state:in-progress
  state:ready-for-ticket-review
  state:ticket-reviewed
  state:ready-for-feature-review
  state:blocked
  state:done
  state:ready-for-human
  state:wontfix
)

for l in "${STATE_LABELS[@]}"; do
  gh issue edit "$NUM" --repo "$REPO" --remove-label "$l" 2>/dev/null || true
done
gh issue edit "$NUM" --repo "$REPO" --add-label "$NEW"

# Enforce the `verified`/`unverified` binary pair on every transition.
# Decision matrix:
#   - state:ready-for-ticket-review + gate passed -> verified
#   - state:ready-for-ticket-review + gate failed -> unverified (strip stale verified)
#   - state:in-progress                           -> unverified (re-arm for re-work)
#   - state:ticket-reviewed | state:ready-for-feature-review | state:done
#     -> carry forward: keep `verified` if already present, else `unverified`.
#        These post-verification states must not re-seed `unverified`, otherwise
#        spec `feature-complete` (which filters on `verified`) breaks.
#   - any other state (needs-triage, needs-info, ready-for-agent, blocked,
#     wontfix, ready-for-human) -> unverified (no implicit verification claim).
LABELS_NOW=$(gh issue view "$NUM" --repo "$REPO" --json labels -q '.labels[].name' 2>/dev/null || true)
HAS_VERIFIED=false
if grep -qx 'verified' <<<"$LABELS_NOW"; then HAS_VERIFIED=true; fi

VERIFY_LABEL="unverified"
case "$NEW" in
  state:ready-for-ticket-review)
    if [[ "$GATE_PASS" == "true" ]]; then
      VERIFY_LABEL="verified"
    else
      VERIFY_LABEL="unverified"
    fi
    ;;
  state:ticket-reviewed|state:ready-for-feature-review|state:done)
    if [[ "$HAS_VERIFIED" == "true" ]]; then
      VERIFY_LABEL="verified"
    else
      VERIFY_LABEL="unverified"
    fi
    ;;
  *)
    VERIFY_LABEL="unverified"
    ;;
esac

OTHER="unverified"
if [[ "$VERIFY_LABEL" == "unverified" ]]; then OTHER="verified"; fi

# Ensure both labels exist in the repo before swap (idempotent). On a fresh repo
# the first --remove-label may otherwise 404 on a label that was never seeded.
gh label create "verified"   --repo "$REPO" --force 2>/dev/null || true
gh label create "unverified" --repo "$REPO" --force 2>/dev/null || true

# Atomic swap: remove the other, add this — single gh issue edit, so consumers
# never observe a moment with neither label.
gh issue edit "$NUM" --repo "$REPO" --remove-label "$OTHER" --add-label "$VERIFY_LABEL" 2>/dev/null || true

# Bail with non-zero exit on a BLOCKED transition so the caller's `set -e` (and
# the orchestrator's BLOCKED surfacing) sees the gate failure. The state label
# and verification swap above still ran, so a stale `verified` cannot survive a
# NEEDS_CHANGES / gate-failed cycle.
if [[ "$GATE_PASS" != "true" ]]; then
  exit 1
fi

echo "OK: $REPO#$NUM -> $NEW (verify=$VERIFY_LABEL)"
