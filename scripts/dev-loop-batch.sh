#!/usr/bin/env bash
# Emit a compact JSON array of all currently runnable OpenCode child issues for feature:<slug>
# in two gh API calls (DAG-respecting). A ticket is runnable when it is OPEN, carries both
# `feature:<slug>` AND `state:ready-for-agent`, and every dependency is satisfied.
#
# Dependency SOURCES (in priority order):
#   1. The `**Blocked by:** #n, #m` line (or `## Blocked by` section) in the issue body —
#      the human contract written by fanout/sync-fanout-bodies. `**Blocked by:** (none)`
#      explicitly means no dependencies and WINS over YAML.
#   2. When the Blocked-by line is absent (body rewrites such as issue-expand have dropped
#      it): `depends_on:` task ids in the `opencode-task-yaml` fence, resolved to sibling
#      issue numbers via each issue's own `task_id`. An unresolvable task id counts as
#      unsatisfied (safe direction).
#
# A dependency is SATISFIED when ANY of:
#   - the dep issue is CLOSED, or
#   - the dep issue carries `state:done`, or
#   - the dep's ticket sub-PR is MERGED with head ref `opencode/ticket-<dep>-<slug>-*`.
# The merged-sub-PR signal is required by close-at-merge: ticket issues stay OPEN for the
# whole dev loop (closing is owned by spec feature-complete), so the in-loop completion
# signal is the merged sub-PR into opencode/feat-<slug>.
#
# Output shape: [{number, title, url, repo}, ...] — one compact line, sorted by number.
# Deliberately relay-safe: entries NEVER carry issue bodies or opencode-task-yaml meta.
# The developer Task that runs this script relays stdout verbatim; bodies are fetched only to
# parse dependencies and are never emitted. Coder sessions reconstruct full ticket context
# from GitHub (ticket-lifecycle §0) and worktree-manager derives <abbrev> from the title itself.
#
# Exit codes: 0 = runnable batch on stdout; 1 = nothing runnable (batch loop done);
#             2 = gh/API failure — surface verbatim, never treat as "all done".
# Usage: dev-loop-batch.sh <feature_slug_without_prefix> [--repo OWNER/REPO]
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

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
ISSUES_FILE="$WORK/issues.json"
MERGED_FILE="$WORK/merged.json"
CANDS_FILE="$WORK/candidates.ndjson"
STATES_FILE="$WORK/states.json"
TASKDEP_FILE="$WORK/taskdep.tsv"

# gh call 1 of 2: OPEN and CLOSED feature issues. Closed siblings resolve dependencies
# locally (fanout deps are same-feature tickets). -L caps the combined result; 200 covers
# any realistic fanout.
if ! gh issue list --repo "$REPO" -L 200 --state all --label "$FEAT" \
  --json number,title,url,state,labels,body >"$ISSUES_FILE" 2>"$WORK/gh.err"; then
  echo "dev-loop-batch: gh issue list failed for ${REPO} label ${FEAT}" >&2
  cat "$WORK/gh.err" >&2
  exit 2
fi

# gh call 2 of 2: merged PR head refs (the close-at-merge in-loop completion signal).
if ! gh pr list --repo "$REPO" --state merged -L 200 --json headRefName >"$MERGED_FILE" 2>"$WORK/ghpr.err"; then
  echo "dev-loop-batch: gh pr list (merged) failed for ${REPO}" >&2
  cat "$WORK/ghpr.err" >&2
  exit 2
fi

# number -> {state, done} map for local dep resolution.
jq -c 'map({key: (.number | tostring),
            value: {state: .state, done: any(.labels[]?; .name == "state:done")}})
       | from_entries' "$ISSUES_FILE" >"$STATES_FILE"

# Per-issue task_id + depends_on parsed from the opencode-task-yaml fence:
# TASKDEP_FILE = number <TAB> task_id <TAB> dep,dep,...  (machine-contract dep source).
jq -r '.[] | "@@@OC_ISSUE@@@ \(.number)", .body' "$ISSUES_FILE" | awk '
  /^@@@OC_ISSUE@@@ / {
    if (rec) flush()
    num = $2; tid = ""; dc = 0; rec = 1; intask = 0; inlist = 0
    next
  }
  /^```opencode-task-yaml[[:space:]]*$/ { intask = 1; next }
  intask && /^```/ { intask = 0; inlist = 0; next }
  intask {
    if ($0 ~ /^task_id:/) {
      tid = $0; sub(/^task_id:[[:space:]]*/, "", tid); gsub(/[[:space:]]+$/, "", tid)
    } else if ($0 ~ /^depends_on:/) {
      inlist = 0
      rest = $0; sub(/^depends_on:[[:space:]]*/, "", rest)
      if (rest ~ /^\[/) {
        gsub(/[\[\]]/, "", rest)
        n = split(rest, arr, ",")
        for (i = 1; i <= n; i++) {
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", arr[i])
          if (arr[i] != "") deps[++dc] = arr[i]
        }
      } else if (rest != "") {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", rest)
        if (rest != "") deps[++dc] = rest
      } else {
        inlist = 1
      }
    } else if (inlist) {
      if ($0 ~ /^[[:space:]]*-[[:space:]]*/) {
        item = $0; sub(/^[[:space:]]*-[[:space:]]*/, "", item); gsub(/[[:space:]]+$/, "", item)
        if (item != "") deps[++dc] = item
      } else {
        inlist = 0
      }
    }
  }
  function flush() {
    depstr = ""
    for (i = 1; i <= dc; i++) depstr = depstr (i > 1 ? "," : "") deps[i]
    printf "%s\t%s\t%s\n", num, tid, depstr
  }
  END { if (rec) flush() }
' >"$TASKDEP_FILE"

# Candidates: OPEN + state:ready-for-agent, sorted by number.
jq -c 'sort_by(.number)
  | .[]
  | select(.state == "OPEN")
  | select(any(.labels[]?; .name == "state:ready-for-agent"))
  | {number, title, url, body}' "$ISSUES_FILE" >"$CANDS_FILE" || true

blocked_by_section() {
  local body="$1" section
  section=$(printf '%s' "$body" | awk '/^## Blocked by$/{found=1; next} found && /^## /{exit} found{print}' || true)
  if [[ -z "$section" ]]; then
    section=$(printf '%s' "$body" | grep '^\*\*Blocked by:\*\*' | head -1 || true)
  fi
  printf '%s' "$section"
}

taskid_deps() { # issue number -> comma-joined dep task ids
  awk -F'\t' -v n="$1" '$1 == n {print $3; exit}' "$TASKDEP_FILE"
}

number_for_taskid() { # task id -> issue number ("" when unknown in this feature set)
  awk -F'\t' -v t="$1" '$2 == t {print $1; exit}' "$TASKDEP_FILE"
}

# True when the dep's ticket sub-PR (branch opencode/ticket-<dep>-<slug>-*) has merged.
merged_subpr() {
  local d="$1"
  [[ $(jq -r --arg p "opencode/ticket-${d}-${SLUG}-" \
    'map(.headRefName // "") | any(.[]; startswith($p))' "$MERGED_FILE") == "true" ]]
}

# 0 = dependency satisfied (CLOSED, state:done, or merged sub-PR); 1 = not satisfied.
dep_satisfied() {
  local d="$1" info st done
  info=$(jq -r --arg k "$d" \
    '(.[$k] // {}) | "\(.state // "")\t\(if (.done // false) then "1" else "0" end)"' "$STATES_FILE")
  st="${info%%$'\t'*}"
  done="${info##*$'\t'}"
  if [[ -z "$st" ]]; then
    # Not in this feature's issue set (rare: cross-feature ref) — single fallback lookup.
    info=$(gh issue view "$d" --repo "$REPO" --json state,labels \
      -q '[(.state), (if any(.labels[]?; .name == "state:done") then "1" else "0" end)] | @tsv' \
      2>/dev/null || true)
    st=$(printf '%s' "$info" | cut -f1)
    done=$(printf '%s' "$info" | cut -f2)
    if [[ -z "$st" ]]; then
      st="OPEN" # lookup failed — treat unsatisfied (safe direction)
      done="0"
    fi
  fi
  if [[ "$st" == "CLOSED" || "$done" == "1" ]]; then
    return 0
  fi
  merged_subpr "$d"
}

# 0 = every dependency satisfied (or no dependencies); 1 = at least one dep unsatisfied.
# $1 = issue body, $2 = issue number (for the YAML task-id fallback).
deps_satisfied() {
  local body="$1" number="$2" section deps d tids tid dn
  section=$(blocked_by_section "$body")
  if [[ -n "$section" ]]; then
    if printf '%s' "$section" | grep -qiE '\bnone\b|\(none\)'; then
      return 0
    fi
    deps=$(printf '%s' "$section" | grep -oE '#[0-9]+' | tr -d '#' || true)
  else
    # Blocked-by line absent (a body rewrite dropped it) — use the machine contract:
    # depends_on task ids resolved to sibling issue numbers.
    deps=""
    tids=$(taskid_deps "$number")
    for tid in ${tids//,/ }; do
      dn=$(number_for_taskid "$tid")
      if [[ -z "$dn" ]]; then
        return 1 # unresolvable dep task id — treat unsatisfied (safe direction)
      fi
      deps="${deps:+$deps }$dn"
    done
  fi
  [[ -n "$deps" ]] || return 0
  for d in $deps; do
    dep_satisfied "$d" || return 1
  done
  return 0
}

OUT='[]'
while IFS= read -r cand; do
  [[ -n "$cand" ]] || continue
  number=$(printf '%s' "$cand" | jq -r .number)
  title=$(printf '%s' "$cand" | jq -r .title)
  url=$(printf '%s' "$cand" | jq -r .url)
  body=$(printf '%s' "$cand" | jq -r .body)
  if ! deps_satisfied "$body" "$number"; then
    continue
  fi
  entry=$(jq -c -n --argjson n "$number" --arg t "$title" --arg u "$url" --arg r "$REPO" \
    '{number: $n, title: $t, url: $u, repo: $r}')
  OUT=$(jq -c --argjson e "$entry" '. + [$e]' <<<"$OUT")
done <"$CANDS_FILE"

count=$(jq 'length' <<<"$OUT")
if [[ "$count" -eq 0 ]]; then
  exit 1
fi
printf '%s\n' "$OUT"
