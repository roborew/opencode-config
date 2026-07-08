#!/usr/bin/env bash
# GitHub Project board helpers (org-wide via GH_PROJECT env var).
# Source from publish-prd-issue, fanout, sync-fanout-bodies.

# Parse GH_PROJECT into GH_PROJECT_OWNER and GH_PROJECT_NUMBER.
# Accepts: full URL, owner/number, owner#number. No-op when unset.
github_project_parse_env() {
  GH_PROJECT_OWNER=""
  GH_PROJECT_NUMBER=""
  [[ -n "${GH_PROJECT:-}" ]] || return 0

  local raw="${GH_PROJECT}"
  if [[ "$raw" =~ ^https?://github\.com/(orgs/)?([^/]+)/projects/([0-9]+) ]]; then
    GH_PROJECT_OWNER="${BASH_REMATCH[2]}"
    GH_PROJECT_NUMBER="${BASH_REMATCH[3]}"
  elif [[ "$raw" =~ ^([^/#]+)[/#]([0-9]+)$ ]]; then
    GH_PROJECT_OWNER="${BASH_REMATCH[1]}"
    GH_PROJECT_NUMBER="${BASH_REMATCH[2]}"
  else
    echo "WARN: GH_PROJECT not recognized (expected URL or owner/number): $raw" >&2
    return 1
  fi
}

# Add a GitHub issue or PR URL to the configured project board.
# Idempotent: ignores "already exists" errors.
github_project_add_issue() {
  local url="${1:?issue url required}"
  github_project_parse_env || return 0
  [[ -n "$GH_PROJECT_OWNER" && -n "$GH_PROJECT_NUMBER" ]] || return 0

  local err
  if ! err=$(gh project item-add "$GH_PROJECT_NUMBER" \
    --owner "$GH_PROJECT_OWNER" \
    --url "$url" 2>&1); then
    if echo "$err" | grep -qiE 'already|exists|duplicate'; then
      return 0
    fi
    echo "WARN: failed to add $url to project ${GH_PROJECT_OWNER}/${GH_PROJECT_NUMBER}: $err" >&2
    return 0
  fi
}

# Link child issue URL as sub-issue of parent issue URL. Idempotent.
github_project_link_subissue() {
  local parent_url="${1:?parent url required}"
  local child_url="${2:?child url required}"

  local err
  if ! err=$(gh issue edit "$parent_url" --add-sub-issue "$child_url" 2>&1); then
    if echo "$err" | grep -qiE 'already|exists|duplicate|sub-issue'; then
      return 0
    fi
    echo "WARN: failed to link sub-issue $child_url under $parent_url: $err" >&2
    return 0
  fi
}

# Batch-link all child URLs to parent. Comma-separated child URLs.
github_project_reconcile_subissues() {
  local parent_url="${1:?parent url required}"
  local child_urls_csv="${2:-}"
  [[ -n "$child_urls_csv" ]] || return 0

  # Process each child URL individually (gh issue edit --add-sub-issue takes one URL at a time)
  local IFS=','
  local child_url
  for child_url in $child_urls_csv; do
    [[ -n "$child_url" ]] || continue
    local err
    if ! err=$(gh issue edit "$parent_url" --add-sub-issue "$child_url" 2>&1); then
      # Only treat true duplicate/already-exists as success; fail on other errors
      if echo "$err" | grep -qiE '(already exists|already a sub-issue|duplicate sub-issue)'; then
        continue
      fi
      echo "WARN: failed to link sub-issue $child_url under $parent_url: $err" >&2
      return 1
    fi
  done
}

# Collect child issue URLs from task map file (task_id TAB issue_num) + repo lookup.
# Usage: github_project_collect_child_urls <task_map_file> <tickets_json_file>
# Prints comma-separated issue URLs.
github_project_collect_child_urls() {
  local map_file="${1:?map file required}"
  local tickets_json="${2:?tickets json required}"
  local urls=()
  local tid repo num url

  while IFS=$'\t' read -r tid num; do
    [[ -n "$tid" && -n "$num" ]] || continue
    repo=$(jq -r --arg id "$tid" '.[] | select(.id==$id) | .repo' "$tickets_json")
    [[ -n "$repo" && "$repo" != "null" ]] || continue
    url=$(gh issue view "$num" --repo "$repo" --json url -q .url 2>/dev/null || true)
    [[ -n "$url" ]] && urls+=("$url")
  done <"$map_file"

  if [[ ${#urls[@]} -gt 0 ]]; then
    local IFS=','
    echo "${urls[*]}"
  fi
}
