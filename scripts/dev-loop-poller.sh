#!/usr/bin/env bash
# Server-host cron poller. Every run: for each configured repo (env
# DEV_LOOP_REPOS as comma-separated owner/name list, or arg), run the watch
# logic, diff against ~/.local/state/opencode/dev-loop/<owner-repo>.json; on
# non-empty delta, promptAsync the newest agent=orchestrate session in the
# impl repo's main-checkout directory with a DEV_LOOP_WAKE message; update the
# state file. Idempotent — uses the state file to dedupe wake messages per
# (repo, issue, comment-id) tuple.
#
# Deployment: cron or systemd timer on the opencode-server host, ~2-min
# interval. See docs/RUNBOOK.md for the unit example.
#
# Usage: dev-loop-poller.sh [--repos OWNER/REPO,OWNER/REPO] [--config-dir <dir>]
# Env:
#   DEV_LOOP_REPOS                 comma-separated owner/name list
#   OPENCODE_SERVER_USERNAME       required (basic auth)
#   OPENCODE_SERVER_PASSWORD       required (basic auth)
#   OPENCODE_SERVER_PORT           default 4098 (loopback)
#   OPENCODE_CONFIG                default ~/.config/opencode (locates watch.sh)
#   DEV_LOOP_STATE_DIR             default ~/.local/state/opencode/dev-loop
set -euo pipefail
USER_ARG=""
CONFIG_DIR_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repos) USER_ARG="${2:?}"; shift 2 ;;
    --config-dir) CONFIG_DIR_ARG="${2:?}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

: "${OPENCODE_SERVER_USERNAME:?OPENCODE_SERVER_USERNAME required}"
: "${OPENCODE_SERVER_PASSWORD:?OPENCODE_SERVER_PASSWORD required}"
PORT="${OPENCODE_SERVER_PORT:-4098}"
OC="${OPENCODE_CONFIG:-$HOME/.config/opencode}"
WATCH_SH="$OC/skills/github-issue-run/lib/dev-loop-watch.sh"
STATE_DIR="${DEV_LOOP_STATE_DIR:-$HOME/.local/state/opencode/dev-loop}"
mkdir -p "$STATE_DIR"

if [[ -n "$USER_ARG" ]]; then
  REPOS="$USER_ARG"
elif [[ -n "${DEV_LOOP_REPOS:-}" ]]; then
  REPOS="$DEV_LOOP_REPOS"
else
  echo "no repos configured (set DEV_LOOP_REPOS or pass --repos)" >&2
  exit 2
fi

BASIC_AUTH="$(printf '%s:%s' "$OPENCODE_SERVER_USERNAME" "$OPENCODE_SERVER_PASSWORD" | base64)"

# Resolve impl repo main-checkout directory from gh. The orchestrator session
# lives in the main checkout, not a ticket/feature worktree.
resolve_main_checkout() {
  local repo="$1" dir
  dir=$(gh repo view "$repo" --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
  [[ -n "$dir" ]] || return 1
  echo "$HOME/code/${dir##*/}"
}

# Find the newest agent=orchestrate session for a project directory via the v2
# session.list API (filter by directory, agent, no parentID). Returns the
# session id or empty.
find_orchestrate_session() {
  local project_dir="$1" sid
  # /session?directory=<uri-encoded>
  local encoded
  encoded=$(printf '%s' "$project_dir" | python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read(), safe=""))')
  local list_json
  list_json=$(curl -sf -H "Authorization: Basic $BASIC_AUTH" \
    "http://127.0.0.1:${PORT}/session?directory=${encoded}" 2>/dev/null || true)
  [[ -n "$list_json" ]] || return 0
  sid=$(printf '%s' "$list_json" | jq -r '
    [.[] | select((.agent // "") == "orchestrate" and (.parentID // null) == null)]
    | sort_by(.time.created // 0) | reverse | .[0].id // ""' 2>/dev/null || true)
  printf '%s' "$sid"
}

# Find the latest ticket_report: comment id for an issue (used to dedupe wakes).
latest_ticket_report_id() {
  local repo="$1" num="$2"
  gh issue view "$num" --repo "$repo" --comments --json comments -q '
    [.comments[] | select(.body | startswith("ticket_report:"))]
    | last | .id // ""' 2>/dev/null || true
}

# Send DEV_LOOP_WAKE to a session via promptAsync (204 fire-and-forget).
wake_session() {
  local sid="$1" project_dir="$2" msg="$3"
  local encoded
  encoded=$(printf '%s' "$project_dir" | python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read(), safe=""))')
  local payload
  payload=$(printf '%s' "$msg" | jq -Rsa '{parts: [{type: "text", text: .}], agent: "orchestrate"}')
  curl -sf -o /dev/null -H "Authorization: Basic $BASIC_AUTH" -H 'Content-Type: application/json' \
    -X POST "http://127.0.0.1:${PORT}/session/${sid}/prompt_async?directory=${encoded}" \
    -d "$payload" 2>/dev/null || return 1
  return 0
}

if [[ ! -x "$WATCH_SH" ]] && [[ ! -f "$WATCH_SH" ]]; then
  echo "watch script not found: $WATCH_SH" >&2
  exit 2
fi

OLD_IFS="$IFS"
IFS=','
for repo in $REPOS; do
  IFS="$OLD_IFS"
  repo="$(printf '%s' "$repo" | xargs)"
  [[ -z "$repo" ]] && continue
  [[ "$repo" =~ ^[^/]+/[^/]+$ ]] || { echo "skipping malformed repo: $repo" >&2; continue; }
  slug="${repo#*/}"
  state_file="$STATE_DIR/${repo//\//_}.json"
  prev_seen=""
  [[ -f "$state_file" ]] && prev_seen=$(cat "$state_file" 2>/dev/null || true)
  current="$("$WATCH_SH" "$slug" --repo "$repo" 2>/dev/null || true)"
  if [[ -z "$current" ]]; then
    printf '%s' "$prev_seen" >"$state_file"
    continue
  fi
  printf '%s' "$current" >"$state_file"
  # Detect deltas: any new entry by (number, ticket_report_id) that wasn't in prev_seen.
  delta=$(jq -c --argjson prev "$prev_seen" --argjson cur "$current" '
    $cur
    | map(. as $c
      | (($prev // []) | map(select(.number == $c.number and .ticket_report == $c.ticket_report)) | length) as $matched
      | select($matched == 0))
  ' <<<"{}" 2>/dev/null || printf '%s' "$current")
  [[ "$(printf '%s' "$delta" | jq 'length' 2>/dev/null || echo 0)" -gt 0 ]] || continue
  project_dir="$(resolve_main_checkout "$repo" || true)"
  if [[ -z "$project_dir" ]]; then
    echo "could not resolve main checkout for $repo; skipping wake" >&2
    continue
  fi
  sid="$(find_orchestrate_session "$project_dir" || true)"
  if [[ -z "$sid" ]]; then
    echo "no orchestrate session for $repo ($project_dir); skipping wake" >&2
    continue
  fi
  msg=$(jq -rnc \
    --arg repo "$repo" \
    --arg feat "feature:$slug" \
    --argjson delta "$delta" \
    '"DEV_LOOP_WAKE: { repo: \($repo), feature: \($feat), reason: \"ticket_report delta\" }\n\n" + ($delta | tostring)')
  if wake_session "$sid" "$project_dir" "$msg"; then
    echo "woke $repo session=$sid delta_count=$(printf '%s' "$delta" | jq 'length')"
  else
    echo "wake failed for $repo session=$sid" >&2
  fi
done
IFS="$OLD_IFS"