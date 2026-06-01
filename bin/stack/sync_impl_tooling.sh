#!/usr/bin/env bash
# Sync implementation-repo bins from OpenCode templates.
# Usage: sync_impl_tooling.sh <impl-repo-path>
set -euo pipefail

IMPL="${1:?implementation repo path}"
OC="$(cd "$(dirname "$0")/../.." && pwd)"
TEMPLATE="${OC}/templates/bin"

IMPL="$(cd "$IMPL" && pwd)"
mkdir -p "$IMPL/bin"

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

if [[ "${OPENCODE_SETUP_QUIET:-}" != "1" ]]; then
  echo "==> Syncing impl tooling into $(basename "$IMPL")..."
fi

for script in feature-context issue-expand-bundle orchestrate-readiness-check feature-check; do
  src="${TEMPLATE}/${script}"
  [[ -f "$src" ]] || continue
  install -m0755 "$src" "$IMPL/bin/${script}"
  strip_crlf "$IMPL/bin/${script}"
  if [[ "${OPENCODE_SETUP_QUIET:-}" != "1" ]]; then
    echo "Synced bin/${script}"
  fi
done
