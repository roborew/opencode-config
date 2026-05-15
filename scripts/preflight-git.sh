#!/usr/bin/env bash
# Pipe a proposed shell command through the same guardrails as block-dangerous-git.sh
# Usage: scripts/preflight-git.sh 'git push --force origin main'
# Exit 0 = allowed, 2 = blocked.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
cmd=${*:-}
if [[ -z "$cmd" ]]; then
  echo "Usage: scripts/preflight-git.sh '<shell command>'" >&2
  exit 1
fi
if command -v jq >/dev/null 2>&1; then
  json=$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}')
else
  json=$(printf '{"tool_input":{"command":"%s"}}' "${cmd//\"/\\\"}")
fi
echo "$json" | "$ROOT/block-dangerous-git.sh"
