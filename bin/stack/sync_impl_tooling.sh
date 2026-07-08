#!/usr/bin/env bash
# Deprecated: OpenCode project scripts live in OPENCODE_CONFIG_DIR (use opencode-run).
# Usage: sync_impl_tooling.sh <impl-repo-path>
set -euo pipefail
IMPL="${1:?implementation repo path}"
if [[ "${OPENCODE_SETUP_QUIET:-}" != "1" ]]; then
  echo "==> Skipping impl bin sync for $(basename "$IMPL") (use opencode-run from central config)"
fi
