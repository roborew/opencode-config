#!/usr/bin/env bash
# Read-only verification of linked-worktree env copies (no cp).
# Usage: preflight-worktree-verify.sh
# Env:
#   WORKTREE_ENV_FILES       space-separated basenames (default: ".env .env.local")
#   PREFLIGHT_MAIN_REPO_ROOT optional absolute main-checkout root override
# Emits one JSON object on stdout. Never prints env file contents.
# Exit 0: ok | ok_existing | skipped_*; Exit 1: failed; Exit 2: missing jq
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "preflight-worktree-verify: jq is required" >&2
  exit 2
fi

emit() {
  local status="$1"
  local wt_root="${2:-}"
  local main_root="${3:-}"
  local files_json="${4:-[]}"
  local commands_json="${5:-[]}"

  jq -nc \
    --arg worktree_env "$status" \
    --arg wt_root "$wt_root" \
    --arg main_root "$main_root" \
    --argjson files "$files_json" \
    --argjson commands_run "$commands_json" \
    '{
      worktree_env: $worktree_env,
      wt_root: (if $wt_root == "" then null else $wt_root end),
      main_root: (if $main_root == "" then null else $main_root end),
      files: $files,
      commands_run: $commands_run
    }'
}

commands_json='[]'
add_cmd() {
  commands_json=$(jq -nc --argjson acc "$commands_json" --arg c "$1" '$acc + [$c]')
}

files_json='[]'
add_file() {
  local name="$1" status="$2" source="$3" target="$4" is_regular="$5"
  files_json=$(jq -nc \
    --argjson acc "$files_json" \
    --arg name "$name" \
    --arg status "$status" \
    --arg source "$source" \
    --arg target "$target" \
    --argjson is_regular_file "$is_regular" \
    '$acc + [{
      name: $name,
      status: $status,
      source: $source,
      target: $target,
      is_regular_file: $is_regular_file
    }]')
}

add_cmd "git rev-parse --is-inside-work-tree"
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  emit "skipped_not_git" "" "" "[]" "$commands_json"
  exit 0
fi

wt_root="$(git rev-parse --show-toplevel)"
cd "$wt_root"

add_cmd "git rev-parse --path-format=absolute --git-dir"
git_dir="$(git rev-parse --path-format=absolute --git-dir)"

if [[ "$git_dir" != *"/.git/worktrees/"* ]]; then
  emit "skipped_not_linked_worktree" "$wt_root" "" "[]" "$commands_json"
  exit 0
fi

if [[ -n "${PREFLIGHT_MAIN_REPO_ROOT:-}" ]]; then
  main_root="${PREFLIGHT_MAIN_REPO_ROOT%/}"
  add_cmd "PREFLIGHT_MAIN_REPO_ROOT override"
else
  add_cmd "git rev-parse --path-format=absolute --git-common-dir"
  common="$(git rev-parse --path-format=absolute --git-common-dir)"
  main_root="$(dirname "$common")"
fi

# shellcheck disable=SC2206
files=( ${WORKTREE_ENV_FILES:-.env .env.local} )
had_failed=false
all_existing=true
checked_any=false

for f in "${files[@]}"; do
  [[ -n "$f" ]] || continue
  source_path="${main_root}/${f}"
  target_path="${wt_root}/${f}"

  if [[ ! -e "$source_path" && ! -L "$source_path" ]]; then
    add_cmd "skip missing source: $f"
    continue
  fi

  checked_any=true
  is_regular=false
  status="failed"

  if [[ -f "$target_path" && ! -L "$target_path" ]]; then
    is_regular=true
    # Prefer ok_existing when present; parent may still treat overall as ok.
    status="ok_existing"
    add_cmd "test -f && test ! -L: $f"
  else
    had_failed=true
    all_existing=false
    add_cmd "verify failed: $f missing or symlink"
  fi

  add_file "$f" "$status" "$source_path" "$target_path" "$is_regular"
done

if [[ "$had_failed" == true ]]; then
  emit "failed" "$wt_root" "$main_root" "$files_json" "$commands_json"
  exit 1
fi

if [[ "$checked_any" == true && "$all_existing" == true ]]; then
  emit "ok_existing" "$wt_root" "$main_root" "$files_json" "$commands_json"
else
  emit "ok" "$wt_root" "$main_root" "$files_json" "$commands_json"
fi
exit 0
