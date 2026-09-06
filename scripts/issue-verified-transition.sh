#!/usr/bin/env bash
# Atomically swap the `verified`/`unverified` pair on a GitHub issue.
# This is the ONLY writer of `verified` outside the gate-failed path inside
# `scripts/issue-state-transition.sh` — the coder session calls this from a
# delegated `developer` Task (load: minimal) on `code-review` APPROVED instead
# of running `gh issue edit --add-label verified` inline, so the pair swap is
# never bypassed.
#
# Usage: issue-verified-transition.sh <repo> <issue_number> <verified|unverified>
# Args:
#   1  repo           owner/name (e.g. "acme/widgets")
#   2  issue_number   GitHub issue number
#   3  direction      "verified" to mark the latest code-review APPROVED applies,
#                     "unverified" to clear a stale `verified` (e.g. NEEDS_CHANGES
#                     on the final-gate full-suite, or operator override)
#
# Invocation shape (from a delegated `developer` Task inside the coder session):
#   bash "$OC/scripts/issue-verified-transition.sh" "<repo>" "<issue_number>" verified
# No OPENCODE_EXPECT_* env vars needed — the developer is already in the right
# worktree, just like `issue-state-transition.sh`.
set -euo pipefail
REPO="${1:?repo owner/name}"
NUM="${2:?issue number}"
DIR="${3:?target: verified|unverified}"

case "$DIR" in
  verified|unverified) ;;
  *)
    echo "BLOCKED: third arg must be 'verified' or 'unverified' (got: $DIR)" >&2
    exit 1
    ;;
esac

OTHER="unverified"
if [[ "$DIR" == "unverified" ]]; then OTHER="verified"; fi

gh label create "verified"   --repo "$REPO" --force 2>/dev/null || true
gh label create "unverified" --repo "$REPO" --force 2>/dev/null || true

gh issue edit "$NUM" --repo "$REPO" --remove-label "$OTHER" --add-label "$DIR" 2>/dev/null || true

echo "OK: $REPO#$NUM -> $DIR"
