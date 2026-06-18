#!/usr/bin/env bash
# Batch triage helpers — requires gh, jq. Repo default: current gh repo.
set -euo pipefail

OC="${OPENCODE_CONFIG:-$HOME/.config/opencode}"
# shellcheck source=../../../scripts/lib/shared.sh
source "${OC}/scripts/lib/shared.sh"

REPO="${TRIAGE_REPO:-$(gh_current_repo 2>/dev/null || true)}"
if [[ -z "$REPO" ]]; then
  echo "usage: TRIAGE_REPO=owner/name $0 <command> [args]" >&2
  exit 1
fi

cmd_list_needs_triage() {
  gh issue list --repo "$REPO" --label "state:needs-triage" --json number,title,labels --jq '.[] | "#\(.number) \(.title)"'
}

cmd_transition() {
  local num="${1:?issue number}"
  local to="${2:?target state label e.g. state:ready-for-agent}"
  transition_issue_state "$REPO" "$num" "$to"
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
