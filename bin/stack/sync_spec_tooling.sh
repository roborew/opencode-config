#!/usr/bin/env bash
# Align spec repo documentation and GitHub scaffolding (no bin/ copies).
# Usage: sync_spec_tooling.sh [--check-only] <spec-repo-path>
# Exit: 0 ok, 3 registry incomplete, 6 PRD validation errors
set -euo pipefail
CHECK_ONLY=false
if [[ "${1:-}" == "--check-only" ]]; then
  CHECK_ONLY=true
  shift
fi
SPEC="${1:?spec repo path}"
OC="$(cd "$(dirname "$0")/../.." && pwd)"
TEMPLATE="${OC}/templates/spec-repo"
MIGRATE="${OC}/bin/lib/migrate_repos_registry.py"
VALIDATE="${OC}/bin/project/spec/lib/validate_tickets.py"

SPEC="$(cd "$SPEC" && pwd)"

if [[ ! -d "$TEMPLATE" ]]; then
  echo "ERROR: missing OpenCode template at $TEMPLATE" >&2
  exit 1
fi

if ! [[ -d "$SPEC/docs/prd" || -f "$SPEC/docs/agents/repos.md" ]]; then
  echo "ERROR: $SPEC does not look like a spec repo" >&2
  exit 1
fi

if [[ "$CHECK_ONLY" == "true" ]]; then
  REGISTRY="$SPEC/docs/agents/repos.md"
  [[ -f "$REGISTRY" ]] || { echo "INCOMPLETE: missing $REGISTRY"; exit 3; }
  python3 "$MIGRATE" "$REGISTRY" --check-only
  if [[ -f "$VALIDATE" ]] && command -v yq >/dev/null 2>&1; then
    shopt -s nullglob
    for prd in "$SPEC"/docs/prd/*.md; do
      [[ "$(basename "$prd")" == "_template.md" ]] && continue
      # PRDs are markdown with YAML frontmatter; plain yq sees body --- as extra docs.
      count=$(yq --front-matter=extract '.tickets // [] | length' "$prd" 2>/dev/null | head -n1)
      [[ "${count:-0}" =~ ^[0-9]+$ ]] || count=0
      [[ "$count" -gt 0 ]] || continue
      slug=$(yq --front-matter=extract -r '.slug // ""' "$prd" 2>/dev/null | head -n1)
      [[ -n "$slug" ]] || slug=$(basename "$prd" .md)
      echo "--> validating tickets in $slug"
      yq --front-matter=extract -o=json '.tickets' "$prd" | python3 "$VALIDATE" "$REGISTRY" || exit 6
    done
  fi
  if [[ -d "$SPEC/.opencode" ]]; then
    echo "WARN: $SPEC/.opencode should not exist in a spec repo (remove it; use OPENCODE_CONFIG_DIR only)" >&2
  fi
  echo "==> check-only: ok"
  exit 0
fi

mkdir -p "$SPEC/docs/agents" "$SPEC/docs/prd"

echo "==> Aligning spec repo docs and GitHub scaffolding..."

cp "$TEMPLATE/docs/prd/_template.md" "$SPEC/docs/prd/_template.md"
[[ -f "$TEMPLATE/.gitattributes" ]] && cp "$TEMPLATE/.gitattributes" "$SPEC/.gitattributes"
if [[ -d "$SPEC/.opencode" ]]; then
  echo "WARN: removing stray $SPEC/.opencode (spec repos use OPENCODE_CONFIG_DIR, not project OpenCode config)" >&2
  rm -rf "$SPEC/.opencode"
fi

REGISTRY="$SPEC/docs/agents/repos.md"
if [[ ! -f "$REGISTRY" ]]; then
  cp "$TEMPLATE/docs/agents/repos.md" "$REGISTRY"
fi

REGISTRY_INCOMPLETE=false
python3 "$MIGRATE" "$REGISTRY" || REGISTRY_INCOMPLETE=true

PRD_ERRORS=0
if command -v yq >/dev/null 2>&1 && [[ -f "$VALIDATE" ]]; then
  shopt -s nullglob
  for prd in "$SPEC"/docs/prd/*.md; do
    base=$(basename "$prd")
    [[ "$base" == "_template.md" ]] && continue
    # PRDs are markdown with YAML frontmatter; plain yq sees body --- as extra docs.
    count=$(yq --front-matter=extract '.tickets // [] | length' "$prd" 2>/dev/null | head -n1)
    [[ "${count:-0}" =~ ^[0-9]+$ ]] || count=0
    [[ "$count" -gt 0 ]] || continue
    if ! yq --front-matter=extract -o=json '.tickets' "$prd" | python3 "$VALIDATE" "$REGISTRY"; then
      PRD_ERRORS=$((PRD_ERRORS + 1))
    fi
  done
fi

if [[ "$REGISTRY_INCOMPLETE" == "true" ]]; then
  exit 3
fi
if [[ "$PRD_ERRORS" -gt 0 ]]; then
  exit 6
fi
exit 0
