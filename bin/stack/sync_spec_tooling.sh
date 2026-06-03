#!/usr/bin/env bash
# Sync fanout tooling into a spec repo; optional --check-only.
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
  VALIDATE="$SPEC/bin/lib/validate_tickets.py"
  if [[ -f "$VALIDATE" ]] && command -v yq >/dev/null 2>&1; then
    shopt -s nullglob
    for prd in "$SPEC"/docs/prd/*.md; do
      [[ "$(basename "$prd")" == "_template.md" ]] && continue
      count=$(yq '.tickets // [] | length' "$prd" 2>/dev/null || echo 0)
      [[ "${count:-0}" -gt 0 ]] || continue
      slug=$(yq -r '.slug // ""' "$prd" 2>/dev/null || basename "$prd" .md)
      echo "--> validating tickets in $slug"
      yq -o=json '.tickets' "$prd" | python3 "$VALIDATE" "$REGISTRY" || exit 6
    done
  fi
  if [[ -d "$SPEC/.opencode" ]]; then
    echo "WARN: $SPEC/.opencode should not exist in a spec repo (remove it; use OPENCODE_CONFIG_DIR only)" >&2
  fi
  echo "==> check-only: ok"
  exit 0
fi

mkdir -p "$SPEC/bin/lib" "$SPEC/skills/fanout-issues" "$SPEC/docs/agents" "$SPEC/docs/prd"

echo "==> Syncing spec tooling..."

# Ensure LF shebangs (CRLF breaks `env: bash\r` on macOS/Linux).
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
sync_bin() {
  install -m0755 "$1" "$2"
  strip_crlf "$2"
}

sync_bin "$TEMPLATE/bin/fanout" "$SPEC/bin/fanout"
[[ -f "$TEMPLATE/bin/fanout-audit" ]] && sync_bin "$TEMPLATE/bin/fanout-audit" "$SPEC/bin/fanout-audit"
[[ -f "$TEMPLATE/bin/publish-prd-issue" ]] && sync_bin "$TEMPLATE/bin/publish-prd-issue" "$SPEC/bin/publish-prd-issue"
for lib in "$TEMPLATE"/bin/lib/*; do
  base=$(basename "$lib")
  dest="$SPEC/bin/lib/$base"
  if [[ -f "$lib" ]]; then
    install -m0755 "$lib" "$dest"
    strip_crlf "$dest"
  fi
done
[[ -f "$TEMPLATE/bin/status" ]] && sync_bin "$TEMPLATE/bin/status" "$SPEC/bin/status"
[[ -f "$TEMPLATE/bin/new-prd" ]] && sync_bin "$TEMPLATE/bin/new-prd" "$SPEC/bin/new-prd"
cp "$TEMPLATE/docs/prd/_template.md" "$SPEC/docs/prd/_template.md"
cp "$TEMPLATE/skills/fanout-issues/SKILL.md" "$SPEC/skills/fanout-issues/SKILL.md"
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
if command -v yq >/dev/null 2>&1; then
  shopt -s nullglob
  for prd in "$SPEC"/docs/prd/*.md; do
    base=$(basename "$prd")
    [[ "$base" == "_template.md" ]] && continue
    count=$(yq '.tickets // [] | length' "$prd" 2>/dev/null || echo 0)
    [[ "${count:-0}" -gt 0 ]] || continue
    if ! yq -o=json '.tickets' "$prd" | python3 "$SPEC/bin/lib/validate_tickets.py" "$REGISTRY"; then
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
