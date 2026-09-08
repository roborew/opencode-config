#!/usr/bin/env bash
# Server-host cron poller. Ticket-only durable fallback for waking the develop
# orchestrator when the primary coder ↔ orchestrator path (`session_notify`) is
# unavailable or missed. Every run: for each configured repo (env
# DEV_LOOP_REPOS as comma-separated owner/name list, or arg), discover active
# `feature:<slug>` labels from open issues, run the ticket watcher once per
# active feature, diff against
# ~/.local/state/opencode/dev-loop/<owner-repo>__<feature-slug>.json; on
# non-empty delta, promptAsync the newest agent=orchestrate session in the
# impl repo's main-checkout directory with a DEV_LOOP_WAKE message; update the
# state file. Idempotent — uses per-repo+feature state to dedupe durable wakes.
#
# Deliberately ticket-only: this poller wakes only from ticket watcher deltas.
# It does NOT implement `feature_report:` durable waking.
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
OC="${CONFIG_DIR_ARG:-${OPENCODE_CONFIG:-$HOME/.config/opencode}}"
WATCH_SH="$OC/scripts/dev-loop-watch.sh"
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

# Discover open feature labels for the repo and emit unique slug values
# without the `feature:` prefix. Open issues are the durable source of truth
# for which features are active enough to watch.
discover_feature_slugs() {
  local repo="$1"
  gh issue list --repo "$repo" -L 200 --state open --json labels 2>/dev/null | jq -r '
    [
      .[]
      | .labels[]?
      | .name // empty
      | select(startswith("feature:"))
      | sub("^feature:"; "")
    ]
    | unique
    | .[]
  ' 2>/dev/null || true
}

state_filename() {
  local repo="$1" slug="$2" safe_slug
  safe_slug=$(printf '%s' "$slug" | sed -E 's/[^A-Za-z0-9._-]+/_/g')
  printf '%s/%s__%s.json' "$STATE_DIR" "${repo//\//_}" "$safe_slug"
}

meaningful_delta() {
  local prev="$1" cur="$2"
  jq -c --argjson prev "$prev" --argjson cur "$cur" '
    def same($a; $b):
      ($a.number == $b.number)
      and (($a.ticket_report // "") == ($b.ticket_report // ""))
      and (($a.pr_state // "") == ($b.pr_state // ""))
      and (($a.out_of_band_merged // false) == ($b.out_of_band_merged // false))
      and (($a.verified_drift // false) == ($b.verified_drift // false));
    $cur
    | map(. as $c
      | (((($prev // []) | map(select(same(.; $c))) | length) > 0)) as $matched
      | select($matched | not))
  ' <<<"{}" 2>/dev/null || printf '%s' "$cur"
}

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
read -r -a REPO_LIST <<<"$REPOS"
IFS="$OLD_IFS"

for repo_raw in "${REPO_LIST[@]}"; do
  repo="$(printf '%s' "$repo_raw" | xargs)"
  [[ -z "$repo" ]] && continue
  [[ "$repo" =~ ^[^/]+/[^/]+$ ]] || { echo "skipping malformed repo: $repo" >&2; continue; }

  while IFS= read -r slug; do
    [[ -n "$slug" ]] || continue

    state_file="$(state_filename "$repo" "$slug")"
    prev_seen='[]'
    if [[ -f "$state_file" ]]; then
      prev_seen=$(cat "$state_file" 2>/dev/null || printf '[]')
      jq -e . >/dev/null 2>&1 <<<"$prev_seen" || prev_seen='[]'
    fi

    current="$($WATCH_SH "$slug" --repo "$repo" 2>/dev/null || true)"
    if [[ -z "$current" ]]; then
      printf '%s' "$prev_seen" >"$state_file"
      continue
    fi

    printf '%s' "$current" >"$state_file"

    # Detect meaningful ticket-only deltas: new issue number, ticket_report,
    # pr_state, out_of_band_merged, or verified_drift.
    delta="$(meaningful_delta "$prev_seen" "$current")"
    [[ "$(printf '%s' "$delta" | jq 'length' 2>/dev/null || echo 0)" -gt 0 ]] || continue

    project_dir="$(resolve_main_checkout "$repo" || true)"
    if [[ -z "$project_dir" ]]; then
      echo "could not resolve main checkout for $repo; skipping wake for feature:$slug" >&2
      continue
    fi

    sid="$(find_orchestrate_session "$project_dir" || true)"
    if [[ -z "$sid" ]]; then
      echo "no orchestrate session for $repo ($project_dir); skipping wake for feature:$slug" >&2
      continue
    fi

    msg=$(jq -rnc \
      --arg repo "$repo" \
      --arg feat "feature:$slug" \
      --argjson delta "$delta" \
      --argjson current "$current" '
        ($current | map(select(.verified_drift == true) | .number)) as $drift
        | "DEV_LOOP_WAKE: { repo: \($repo), feature: \($feat), reason: \"ticket delta\""
          + (if ($drift | length) > 0 then ", advisory: VERIFIED_LABEL_MISSING_AT_REVIEW, drift_issues: " + ($drift | tostring) else "" end)
          + " }\n\n"
          + ($delta | tostring)
          + (if ($drift | length) > 0 then "\nVERIFIED_LABEL_MISSING_AT_REVIEW: " + ($drift | tostring) else "" end)
      ')

    if wake_session "$sid" "$project_dir" "$msg"; then
      echo "woke $repo feature:$slug session=$sid delta_count=$(printf '%s' "$delta" | jq 'length')"
    else
      echo "wake failed for $repo feature:$slug session=$sid" >&2
    fi
  done < <(discover_feature_slugs "$repo")
done
