#!/usr/bin/env bash
# Report implementation repo wiring gaps (for --check-only).
# Usage: check_impl_wiring.sh <parent-dir> <org> <app-slug> [discover_all]
set -euo pipefail
PARENT_DIR="$(cd "$1" && pwd)"
ORG="$2"
APP="$3"
DISCOVER_ALL="${4:-false}"
# shellcheck source=common.sh
source "$(dirname "$0")/common.sh"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=read_spec_repo.sh disable=SC1091
source "${ROOT}/bin/lib/read_spec_repo.sh"

SPEC_NAME="${APP}-spec"
GAPS=0

while IFS= read -r local_dir; do
  [[ -z "$local_dir" ]] && continue
  stack_dir_is_spec_repo "$PARENT_DIR" "$local_dir" "${APP}-spec" && continue
  impl="${PARENT_DIR}/${local_dir}"
  [[ -d "$impl/.git" ]] || continue
  missing=()
  [[ -f "$impl/docs/agents/issue-tracker.md" ]] || missing+=("issue-tracker.md")
  read_spec_repo_from_file "$impl/docs/agents/issue-tracker.md" &>/dev/null || missing+=("SPEC_REPO line")
  grep -q '^tmp/' "$impl/.gitignore" 2>/dev/null || missing+=("gitignore scratch paths")
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "INCOMPLETE: ${local_dir}: ${missing[*]}"
    GAPS=$((GAPS + 1))
  else
    echo "OK: ${local_dir}"
  fi
done < <(stack_discover_targets "$PARENT_DIR" "$SPEC_NAME" "$APP" "$DISCOVER_ALL")

if [[ "$GAPS" -gt 0 ]]; then
  exit 4
fi
exit 0
