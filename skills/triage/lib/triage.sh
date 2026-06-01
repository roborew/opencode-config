#!/usr/bin/env bash
# Batch triage helpers — requires gh, jq. Repo default: current gh repo.
set -euo pipefail

REPO="${TRIAGE_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)}"
if [[ -z "$REPO" ]]; then
  echo "usage: TRIAGE_REPO=owner/name $0 <command> [args]" >&2
  exit 1
fi

state_labels=(
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

remove_state_labels() {
  local num="$1"
  local l
  for l in "${state_labels[@]}"; do
    gh issue edit "$num" --repo "$REPO" --remove-label "$l" 2>/dev/null || true
  done
}

cmd_list_needs_triage() {
  gh issue list --repo "$REPO" --label "state:needs-triage" --json number,title,labels --jq '.[] | "#\(.number) \(.title)"'
}

cmd_transition() {
  local num="${1:?issue number}"
  local to="${2:?target state label e.g. state:ready-for-agent}"
  remove_state_labels "$num"
  gh issue edit "$num" --repo "$REPO" --add-label "$to"
  echo "OK: #$num -> $to"
}

case "${1:-}" in
  list-needs-triage) cmd_list_needs_triage ;;
  transition) shift; cmd_transition "$@" ;;
  *)
    echo "commands: list-needs-triage | transition <num> <state:label>" >&2
    exit 2
    ;;
esac
