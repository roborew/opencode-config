# shellcheck shell=bash
# Shared helpers for bin/setup-project (source only).
set -euo pipefail

stack_oc_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}

# Source shared utilities (strip_crlf, gh_current_repo, etc.)
# shellcheck source=../../scripts/lib/shared.sh
source "$(stack_oc_root)/scripts/lib/shared.sh"

# True if dirname is the spec repo for this app (case-insensitive *-spec match or layout).
stack_dir_is_spec_repo() {
  local parent_dir="$1"
  local dir="$2"
  local app_spec_name="$3"
  local path="${parent_dir}/${dir}"
  [[ "$(printf '%s' "$dir" | tr '[:upper:]' '[:lower:]')" == "$(printf '%s' "$app_spec_name" | tr '[:upper:]' '[:lower:]')" ]] && return 0
  [[ "$(printf '%s' "$dir" | tr '[:upper:]' '[:lower:]')" == *-spec ]] && stack_is_spec_repo "$path" && return 0
  return 1
}

# Discover implementation repo directory names under parent_dir.
# Args: parent_dir spec_name [app_slug] [discover_all=false]
# When discover_all is false and app_slug is set, only siblings matching ${app_slug}-* (case-insensitive), excluding *-spec.
stack_discover_targets() {
  local parent_dir="$1"
  local spec_name="$2"
  local app_slug="${3:-}"
  local discover_all="${4:-false}"
  local dir lower prefix
  for dir in "${parent_dir}"/*/; do
    dir="${dir%/}"
    dir="$(basename "$dir")"
    [[ "$dir" == .* ]] && continue
    [[ -d "${parent_dir}/${dir}/.git" ]] || continue
    stack_dir_is_spec_repo "$parent_dir" "$dir" "$spec_name" && continue
    if [[ "$discover_all" != "true" && -n "$app_slug" ]]; then
      lower="$(printf '%s' "$dir" | tr '[:upper:]' '[:lower:]')"
      prefix="$(printf '%s' "$app_slug" | tr '[:upper:]' '[:lower:]')-"
      [[ "$lower" == "${prefix}"* ]] || continue
    fi
    printf '%s\n' "$dir"
  done
}

stack_discover_targets_with_mode() {
  stack_discover_targets "$1" "$2" "${3:-}" "${4:-false}"
}

# Resolve on-disk spec repo path (handles BlocShed-spec vs blocshed-spec).
stack_resolve_spec_dir() {
  local parent_dir="$1"
  local app="$2"
  local canonical="${parent_dir}/${app}-spec"
  if [[ -d "${canonical}/.git" ]]; then
    cd "$canonical" && pwd
    return 0
  fi
  local d base
  for d in "${parent_dir}"/*; do
    [[ -d "$d/.git" ]] || continue
    base="$(basename "$d")"
    stack_dir_is_spec_repo "$parent_dir" "$base" "${app}-spec" || continue
    cd "$d" && pwd
    return 0
  done
  printf '%s\n' "$canonical"
}

stack_normalize_repo() {
  local org="$1"
  local target="$2"
  if [[ "$target" == */* ]]; then
    printf '%s\n' "$target"
  else
    printf '%s/%s\n' "$org" "$target"
  fi
}

stack_local_dir_for_target() {
  local target="$1"
  if [[ "$target" == */* ]]; then
    printf '%s\n' "${target##*/}"
  else
    printf '%s\n' "$target"
  fi
}

stack_spec_repo_path() {
  local parent_dir="$1"
  local app="$2"
  stack_resolve_spec_dir "$parent_dir" "$app"
}

stack_is_spec_repo() {
  local path="$1"
  [[ -d "$path/docs/prd" || -f "$path/docs/agents/repos.md" ]]
}

# owner/name from git remote (prefer gh; fallback parse).
# Delegates to gh_current_repo from scripts/lib/shared.sh.
stack_gh_repo_from_dir() {
  gh_current_repo "$1"
}

# App slug from spec folder (blocshed-spec -> blocshed).
stack_app_slug_from_spec_dir() {
  local spec_dir="$1"
  local base="${spec_dir##*/}"
  local lower
  lower="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"
  if [[ "$lower" == *-spec ]]; then
    printf '%s\n' "${lower%-spec}"
    return 0
  fi
  printf '%s\n' "$lower"
}

# Default app slug: parent folder name, lowercased (blocshed / BlocShed -> blocshed).
stack_default_app_slug() {
  local parent_dir="$1"
  printf '%s\n' "$(basename "$parent_dir" | tr '[:upper:]' '[:lower:]')"
}
