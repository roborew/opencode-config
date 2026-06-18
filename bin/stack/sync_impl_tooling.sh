#!/usr/bin/env bash
# Sync implementation-repo bins from OpenCode templates.
# Usage: sync_impl_tooling.sh <impl-repo-path>
set -euo pipefail

IMPL="${1:?implementation repo path}"
OC="$(cd "$(dirname "$0")/../.." && pwd)"
TEMPLATE="${OC}/templates/bin"

IMPL="$(cd "$IMPL" && pwd)"
mkdir -p "$IMPL/bin" "$IMPL/bin/lib"
OC_LIB="${OC}/bin/lib"

# shellcheck source=../../scripts/lib/shared.sh
source "${OC}/scripts/lib/shared.sh"

if [[ "${OPENCODE_SETUP_QUIET:-}" != "1" ]]; then
  echo "==> Syncing impl tooling into $(basename "$IMPL")..."
fi

for lib in read_spec_repo.sh fetch_spec_prd.sh; do
  src="${OC_LIB}/${lib}"
  [[ -f "$src" ]] || continue
  install -m0644 "$src" "$IMPL/bin/lib/${lib}"
  strip_crlf "$IMPL/bin/lib/${lib}"
  if [[ "${OPENCODE_SETUP_QUIET:-}" != "1" ]]; then
    echo "Synced bin/lib/${lib}"
  fi
done

for script in feature-context issue-expand-bundle orchestrate-readiness-check feature-check; do
  src="${TEMPLATE}/${script}"
  [[ -f "$src" ]] || continue
  install -m0755 "$src" "$IMPL/bin/${script}"
  strip_crlf "$IMPL/bin/${script}"
  if [[ "${OPENCODE_SETUP_QUIET:-}" != "1" ]]; then
    echo "Synced bin/${script}"
  fi
done
