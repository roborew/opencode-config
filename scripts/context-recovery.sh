#!/usr/bin/env bash
# Re-injects non-negotiables after long sessions; re-reads opencode.md if present.

set -euo pipefail

# shellcheck source=lib/shared.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/shared.sh"

ROOT=$(find_project_root)

echo "=== CONTEXT RECOVERY ==="
echo "Reload from docs/RUNBOOK.md in this repo for full pipeline rules."
echo "Non-negotiables: scribe-only writes for plans/docs; orchestrate does not edit files; verify with evidence."
echo ""

if [[ -f "$ROOT/opencode.md" ]]; then
  echo "=== opencode.md ($ROOT) ==="
  cat "$ROOT/opencode.md"
elif [[ -f "$ROOT/opencode.local.md" ]]; then
  echo "=== opencode.local.md ($ROOT) ==="
  cat "$ROOT/opencode.local.md"
else
  echo "(No opencode.md or opencode.local.md at project root — add one from docs/templates/opencode.md.template)"
fi
echo "=== END CONTEXT RECOVERY ==="
