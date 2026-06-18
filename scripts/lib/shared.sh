# shellcheck shell=bash
# Shared utility functions for OpenCode scripts.
# Source this file: source "$(dirname "$0")/lib/shared.sh" (or adjust path).
# Requires: bash 3.2+, set -euo pipefail in caller.

# --- OpenCode config root ---

# Resolve OpenCode config directory (this repo's root when sourced from scripts/).
oc_root() {
  if [[ -n "${OPENCODE_CONFIG:-}" ]]; then
    printf '%s\n' "$OPENCODE_CONFIG"
  elif [[ -n "${OPENCODE_CONFIG_DIR:-}" ]]; then
    printf '%s\n' "$OPENCODE_CONFIG_DIR"
  else
    printf '%s\n' "${HOME}/.config/opencode"
  fi
}

# --- Project root detection ---

# Walk up from a starting directory to find the project root (has .git, package.json, etc).
# Usage: find_project_root [start_dir]   (default: $PWD)
find_project_root() {
  local dir="${1:-$PWD}"
  [[ -d "$dir" ]] && dir="$(cd "$dir" && pwd)" || dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/package.json" || -f "$dir/pyproject.toml" || -f "$dir/go.mod" || -d "$dir/.git" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  printf '%s\n' "${1:-$PWD}"
}

# --- CRLF normalization ---

# Convert CRLF/CR line endings to LF in a file. No-op if already LF.
# Usage: strip_crlf <filepath>
strip_crlf() {
  python3 -c "
import pathlib, sys
p = pathlib.Path(sys.argv[1])
raw = p.read_bytes()
data = raw.replace(b'\r\n', b'\n').replace(b'\r', b'\n')
if data != raw:
    p.write_bytes(data)
" "$1"
}

# --- GitHub helpers ---

# Get the current repo's owner/name from gh CLI or git remote.
# Usage: gh_current_repo [directory]
# Prints owner/name to stdout; returns 1 if unresolvable.
gh_current_repo() {
  local dir="${1:-.}"
  local name=""
  if command -v gh >/dev/null 2>&1; then
    name="$(cd "$dir" && gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
    if [[ -n "$name" && "$name" == */* ]]; then
      printf '%s\n' "$name"
      return 0
    fi
  fi
  local url=""
  url="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
  [[ -n "$url" ]] || return 1
  case "$url" in
    git@github.com:*)
      name="${url#git@github.com:}"
      name="${name%.git}"
      ;;
    https://github.com/*|http://github.com/*)
      name="${url#https://github.com/}"
      name="${name#http://github.com/}"
      name="${name%.git}"
      ;;
    *)
      return 1
      ;;
  esac
  if [[ "$name" == */* ]]; then
    printf '%s\n' "$name"
    return 0
  fi
  return 1
}

# --- Issue state labels ---

# Canonical state labels used across the pipeline.
OPENCODE_STATE_LABELS=(
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

# Remove all state:* labels from an issue.
# Usage: remove_state_labels <repo> <issue_number>
remove_state_labels() {
  local repo="$1" num="$2"
  local l
  for l in "${OPENCODE_STATE_LABELS[@]}"; do
    gh issue edit "$num" --repo "$repo" --remove-label "$l" 2>/dev/null || true
  done
}

# Transition an issue to a new state label (removes all existing state:* labels first).
# Usage: transition_issue_state <repo> <issue_number> <new_state_label>
transition_issue_state() {
  local repo="$1" num="$2" new="$3"
  remove_state_labels "$repo" "$num"
  gh issue edit "$num" --repo "$repo" --add-label "$new"
}

# --- fetch_spec_prd sourcing ---

# Source fetch_spec_prd.sh from the best available location.
# Usage: source_fetch_spec_prd [bin_dir]
# bin_dir defaults to the script's own bin directory.
source_fetch_spec_prd() {
  local bin_dir="${1:-}"
  local oc_lib
  oc_lib="$(oc_root)/bin/lib"
  if [[ -n "$bin_dir" && -f "${bin_dir}/lib/fetch_spec_prd.sh" ]]; then
    # shellcheck source=/dev/null disable=SC1091
    source "${bin_dir}/lib/fetch_spec_prd.sh"
  elif [[ -f "${oc_lib}/fetch_spec_prd.sh" ]]; then
    # shellcheck source=/dev/null disable=SC1091
    source "${oc_lib}/fetch_spec_prd.sh"
  else
    echo "ERROR: missing fetch_spec_prd.sh (run setup-project / sync_impl_tooling)" >&2
    return 8
  fi
}
