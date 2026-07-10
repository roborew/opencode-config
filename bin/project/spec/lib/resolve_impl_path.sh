#!/usr/bin/env bash
# Resolve owner/repo to absolute sibling impl path (from spec repo cwd or SPEC_ROOT).
# Usage (source): resolve_impl_path owner/repo
#   → sets IMPL_ABS_PATH, IMPL_REPO; exits 0 or 2
# Usage (exec): resolve_impl_path.sh owner/repo  → prints absolute path
set -euo pipefail

_resolve_impl_path() {
  local target="${1:?owner/repo required}"
  local spec_root="${SPEC_ROOT:-}"
  if [[ -z "$spec_root" ]]; then
    spec_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  fi
  [[ -n "$spec_root" ]] || {
    echo "ERROR: resolve_impl_path: not in a git repo and SPEC_ROOT unset" >&2
    return 2
  }

  local parent_dir repo_name candidate
  parent_dir="$(dirname "$spec_root")"
  repo_name="${target##*/}"
  candidate="${parent_dir}/${repo_name}"

  if [[ ! -d "${candidate}/.git" ]]; then
    echo "ERROR: impl sibling not found: ${candidate} (expected ../${repo_name} beside spec repo)" >&2
    echo "       Ensure repo is cloned as a sibling of the spec repo." >&2
    return 2
  fi

  IMPL_REPO="$target"
  IMPL_ABS_PATH="$(cd "$candidate" && pwd)"
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  _resolve_impl_path "$1"
  printf '%s\n' "$IMPL_ABS_PATH"
fi
