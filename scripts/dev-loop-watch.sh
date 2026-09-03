#!/usr/bin/env bash
# Per-issue watcher for the develop orchestrator. Poll-only (no server auth
# needed) — emits a JSON array of open issues for feature:<slug> in any active
# state label, with PR URL (if any), latest ticket_report: comment summary,
# and an `out_of_band_merged` flag set when a sub-PR has been merged via the
# GitHub UI (state MERGED) without a prior state:ticket-reviewed transition
# (the orchestrator treats this as an implicit human approval and sets
# state:ticket-reviewed before running §5d cleanup).
#
# Usage: dev-loop-watch.sh <feature_slug_without_prefix> [--repo OWNER/REPO]
# Output: [{number, state, title, pr_url, pr_state, ticket_report_summary, out_of_band_merged}, ...]
# Exit 1 with empty output when there is nothing to report.
set -euo pipefail
SLUG="${1:?feature slug required}"
shift || true
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
[[ -n "$REPO" ]] || REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
FEAT="feature:${SLUG}"

ACTIVE_STATES=(
  state:in-progress
  state:ready-for-ticket-review
  state:ticket-reviewed
  state:blocked
)

STUBS_FILE=$(mktemp)
trap 'rm -f "$STUBS_FILE"' EXIT

gh issue list --repo "$REPO" -L 200 --label "$FEAT" --state open \
  --json number,title,labels 2>/dev/null | jq -c --arg fe "$FEAT" '
    sort_by(.number)
    | .[]
    | select(.labels[]?.name == $fe)
    | {number, title, state: (.labels[] | select(startswith("state:")) | .name) // ""}
  ' >"$STUBS_FILE" || true

if [[ ! -s "$STUBS_FILE" ]]; then
  exit 1
fi

OUT='[]'
while IFS= read -r stub; do
  [[ -n "$stub" ]] || continue
  state=$(printf '%s' "$stub" | jq -r .state)
  case "$state" in
    state:in-progress|state:ready-for-ticket-review|state:ticket-reviewed|state:blocked) ;;
    *) continue ;;
  esac
  number=$(printf '%s' "$stub" | jq -r .number)
  title=$(printf '%s' "$stub" | jq -r .title)
  branch="opencode/ticket-${number}-${SLUG}-$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' | cut -c1-32)"
  pr_json=$(gh pr list --repo "$REPO" --state all --head "$branch" --json url,state,mergedAt 2>/dev/null || true)
  pr_url=$(printf '%s' "$pr_json" | jq -r '.[0].url // ""' 2>/dev/null || true)
  pr_state=$(printf '%s' "$pr_json" | jq -r '.[0].state // ""' 2>/dev/null || true)
  # Out-of-band merge detection: PR MERGED while the issue label still
  # reports a pre-merge state. The orchestrator (§5e) treats this as an
  # implicit human approval and sets state:ticket-reviewed before cleanup.
  out_of_band_merged="false"
  if [[ "$pr_state" == "MERGED" && "$state" != "state:ticket-reviewed" && "$state" != "state:ready-for-feature-review" && "$state" != "state:done" ]]; then
    out_of_band_merged="true"
  fi
  ticket_report=$(gh issue view "$number" --repo "$REPO" --comments --json comments -q '
    [.comments[]
      | select(.body | startswith("ticket_report:"))
      | .body]
    | last // ""' 2>/dev/null || true)
  ticket_report_summary=$(printf '%s' "$ticket_report" | awk '
    /^ticket_report:$/{f=1; next}
    f && /^  [a-z_]+:/{print substr($0, 3)}
    f && /^[^ ]/{f=0}
  ' | paste -sd '|' - || true)
  entry=$(jq -c -n \
    --argjson n "$number" \
    --arg t "$title" \
    --arg st "$state" \
    --arg pu "$pr_url" \
    --arg ps "$pr_state" \
    --arg tr "$ticket_report_summary" \
    --argjson oob "$out_of_band_merged" \
    '{number: $n, state: $st, title: $t, pr_url: $pu, pr_state: $ps, ticket_report: $tr, out_of_band_merged: $oob}')
  OUT=$(jq -c --argjson e "$entry" '. + [$e]' <<<"$OUT")
done <"$STUBS_FILE"

count=$(jq 'length' <<<"$OUT")
if [[ "$count" -eq 0 ]]; then
  exit 1
fi
printf '%s\n' "$OUT"