#!/usr/bin/env bash
# Validates agent files vs opencode.json and skills vs agent permissions.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ERR=0

if ! python3 -m json.tool opencode.json >/dev/null 2>&1; then
  echo "ERROR: opencode.json is not valid JSON"
  exit 1
fi

echo "Checking agents/*.md have keys in opencode.json agent block..."
for f in agents/*.md; do
  [[ -f "$f" ]] || continue
  base=$(basename "$f" .md)
  if ! grep -q "\"$base\"" opencode.json; then
    echo "  MISSING: agent key for $base"
    ERR=1
  fi
done

echo "Checking skills referenced in agents exist..."
# Extract quoted skill names from permission.skill lines in agents
while IFS= read -r line; do
  # match "skillname": "allow"
  if [[ "$line" =~ \"([a-z0-9-]+)\"[[:space:]]*:[[:space:]]*\"allow\" ]]; then
    sk="${BASH_REMATCH[1]}"
    if [[ "$sk" == "*" ]]; then continue; fi
    if [[ ! -f "skills/$sk/SKILL.md" ]]; then
      echo "  MISSING skill: skills/$sk/SKILL.md (referenced in agents)"
      ERR=1
    fi
  fi
done < <(grep -h 'skill:' agents/*.md 2>/dev/null || true)

if [[ $ERR -ne 0 ]]; then
  echo "validate-opencode-config: FAILED"
  exit 1
fi
echo "validate-opencode-config: OK"
exit 0
