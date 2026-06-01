#!/usr/bin/env bash
# Print operator next steps after setup-project.
# Usage: print_next_steps.sh <spec-repo-path> <sync-exit-code> [linked-impl-count]
set -euo pipefail
SPEC="${1:?spec repo path}"
CHECK_CODE="${2:-0}"
LINKED="${3:-0}"
OC="$(cd "$(dirname "$0")/../.." && pwd)"
SPEC="$(cd "$SPEC" && pwd)"
PARENT="$(dirname "$SPEC")"

echo ""
echo "========================================"
if [[ "$CHECK_CODE" -eq 6 ]]; then
  echo "Shell bootstrap finished with PRD validation errors."
  echo ""
  echo "  Fix ticket/registry issues in the spec repo, then re-run:"
  echo "  \"$OC/bin/setup-project\" --check-only \"$PARENT\""
  exit 0
fi

if [[ "$CHECK_CODE" -eq 3 ]]; then
  echo "Shell bootstrap complete."
  if [[ "$LINKED" -gt 0 ]]; then
    echo ""
    echo "  Done: spec tooling synced; ${LINKED} implementation repo(s) linked."
  else
    echo ""
    echo "  Done: spec tooling synced."
  fi
  echo "  Next (OpenCode): architect → setup-project — fill application_role and"
  echo "  capabilities in docs/agents/repos.md (normal on first run)."
  echo ""
  echo "  cd \"$SPEC\" && opencode"
  echo ""
  echo "  Re-check shell wiring anytime:"
  echo "  \"$OC/bin/setup-project\" --check-only \"$PARENT\""
  exit 0
fi

echo "Stack bootstrap complete."
if [[ "$LINKED" -gt 0 ]]; then
  echo ""
  echo "  Linked ${LINKED} implementation repo(s); registry and tooling are ready."
fi

echo ""
echo "Next:"
echo "  cd \"$SPEC\" && opencode"
echo "  # In architect:"
echo "  #   Run setup-project"
echo ""
echo "Validate anytime (from project parent ${PARENT}):"
echo "  \"$OC/bin/setup-project\" --check-only \"${PARENT}\""
echo "  # Or if OpenCode bin/ is on PATH:"
echo "  setup-project --check-only \"${PARENT}\""
echo ""
echo "Pipeline: docs/FEATURE-PIPELINE.md"
echo "  grill-me → to-prd → bin/fanout → issue-expand → orchestrate → feature-complete"
echo "  PRD edits: bin/feature-upgrade <slug> (spec) or feature-upgrade <slug> (project parent)"
