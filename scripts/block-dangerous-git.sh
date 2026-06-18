#!/usr/bin/env bash
# Block dangerous git / shell commands. For hooks that pass JSON on stdin:
#   {"tool_input":{"command":"..."}}
# Self-test:  scripts/block-dangerous-git.sh --self-test
set -euo pipefail

if [[ "${1:-}" == "--self-test" ]]; then
  set +e
  echo '{"tool_input":{"command":"git push --force origin main"}}' | "$0"
  ec=$?
  set -e
  if [[ "$ec" -ne 2 ]]; then
    echo "self-test: expected exit 2 on force push, got $ec" >&2
    exit 1
  fi
  echo '{"tool_input":{"command":"git status"}}' | "$0"
  echo "OK"
  exit 0
fi

INPUT=$(cat || true)
COMMAND=""
if command -v jq >/dev/null 2>&1; then
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
else
  COMMAND=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
fi

if [[ -z "$COMMAND" ]]; then
  if [[ -n "$INPUT" ]]; then
    echo "WARN: could not parse command from input; allowing passthrough" >&2
  fi
  exit 0
fi

# DELETE FROM ... without WHERE (heuristic; skips subqueries with WHERE inside)
if echo "$COMMAND" | grep -qiE 'DELETE[[:space:]]+FROM' && ! echo "$COMMAND" | grep -qiE 'WHERE'; then
  echo "BLOCKED: DELETE without WHERE: $COMMAND" >&2
  exit 2
fi

DANGEROUS_PATTERNS=(
  'git[[:space:]]+push[^[:space:]]*[[:space:]]+--force'
  'git[[:space:]]+push[^[:space:]]*[[:space:]]+-f'
  'git[[:space:]]+reset[[:space:]]+--hard'
  'git[[:space:]]+clean[[:space:]]+-fd'
  'git[[:space:]]+clean[[:space:]]+-f([[:space:]]|$)'
  'git[[:space:]]+branch[[:space:]]+-D'
  'git[[:space:]]+checkout[[:space:]]+\.'
  'git[[:space:]]+restore[[:space:]]+\.'
  'rm[[:space:]]+-rf[[:space:]]+/'
  'rm[[:space:]]+-rf[[:space:]]+~(/|$)'
  'DROP[[:space:]]+TABLE'
  'TRUNCATE[[:space:]]+TABLE'
)

for pattern in "${DANGEROUS_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qiE "$pattern"; then
    echo "BLOCKED: matches '$pattern': $COMMAND" >&2
    exit 2
  fi
done

# force-with-lease: blocked unless explicitly allowed
if echo "$COMMAND" | grep -qiE 'git[[:space:]]+push' && echo "$COMMAND" | grep -qiE 'force-with-lease'; then
  if [[ "${OPENCODE_ALLOW_FORCE_PUSH:-}" != "1" ]]; then
    echo "BLOCKED: git push --force-with-lease (set OPENCODE_ALLOW_FORCE_PUSH=1 to allow): $COMMAND" >&2
    exit 2
  fi
fi

exit 0
