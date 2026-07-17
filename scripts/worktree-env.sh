#!/usr/bin/env bash
# Copy root env files from the main checkout into a linked git worktree.
# Usage: worktree-env.sh
# Env:
#   WORKTREE_ENV_FILES       space-separated basenames (default: ".env .env.local")
#   PREFLIGHT_MAIN_REPO_ROOT optional absolute main-checkout root override
# Emits one JSON object on stdout. Never prints env file contents.
# Exit 0: ok | skipped_*; Exit 1: failed_cp; Exit 2: missing jq / not runnable
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "worktree-env: jq is required" >&2
  exit 2
fi

emit() {
  local status="$1"
  local wt_root="${2:-}"
  local main_root="${3:-}"
  local files_json="${4:-[]}"
  local commands_json="${5:-[]}"
  local fix="${6:-}"
  local blocker="${7:-}"

  jq -nc \
    --arg worktree_env "$status" \
    --arg wt_root "$wt_root" \
    --arg main_root "$main_root" \
    --argjson files "$files_json" \
    --argjson commands_run "$commands_json" \
    --arg recommended_env_fix "$fix" \
    --arg blocker_code "$blocker" \
    '{
      worktree_env: $worktree_env,
      wt_root: (if $wt_root == "" then null else $wt_root end),
      main_root: (if $main_root == "" then null else $main_root end),
      files: $files,
      commands_run: $commands_run,
      recommended_env_fix: (if $recommended_env_fix == "" then null else $recommended_env_fix end)
    }
    + (if $blocker_code == "" then {} else {blocker_code: $blocker_code} end)'
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
  add_cmd "linked-worktree check (git_dir does not contain /.git/worktrees/)"
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

for f in "${files[@]}"; do
  [[ -n "$f" ]] || continue
  source_path="${main_root}/${f}"
  target_path="${wt_root}/${f}"
  status=""
  is_regular=false

  if [[ ! -e "$source_path" && ! -L "$source_path" ]]; then
    status="skipped_missing_source"
    add_cmd "skip missing source: $f"
  elif [[ -e "$target_path" || -L "$target_path" ]]; then
    if [[ -f "$target_path" && ! -L "$target_path" ]]; then
      status="ok_existing"
      is_regular=true
      add_cmd "test -f && test ! -L: $f (ok_existing)"
    else
      # Legacy symlink or non-regular target → replace with a real copy.
      # On macOS, cp refuses when a symlink resolves to the same inode as source.
      if [[ -L "$target_path" ]]; then
        add_cmd "rm -f \"$target_path\" (replace symlink)"
        rm -f "$target_path"
      fi
      add_cmd "cp \"$source_path\" \"$target_path\""
      if cp "$source_path" "$target_path" \
        && [[ -f "$target_path" && ! -L "$target_path" ]]; then
        status="ok"
        is_regular=true
        add_cmd "test -f && test ! -L: $f (ok)"
      else
        status="failed_cp"
        had_failed=true
        add_cmd "verify failed after cp: $f"
      fi
    fi
  else
    add_cmd "cp \"$source_path\" \"$target_path\""
    if cp "$source_path" "$target_path" \
      && [[ -f "$target_path" && ! -L "$target_path" ]]; then
      status="ok"
      is_regular=true
      add_cmd "test -f && test ! -L: $f (ok)"
    else
      status="failed_cp"
      had_failed=true
      add_cmd "verify failed after cp: $f"
    fi
  fi

  if [[ -f "$target_path" && ! -L "$target_path" ]]; then
    is_regular=true
  else
    is_regular=false
  fi

  add_file "$f" "$status" "$source_path" "$target_path" "$is_regular"
done

if [[ "$had_failed" == true ]]; then
  emit "failed_cp" "$wt_root" "$main_root" "$files_json" "$commands_json" \
    "Copy env files from main checkout into this worktree (cp \"$main_root/.env\" \"$wt_root/.env\"), ensure targets are regular files, then rerun worktree-env." \
    "ENV_BLOCKED"
  exit 1
fi

emit "ok" "$wt_root" "$main_root" "$files_json" "$commands_json"
exit 0
