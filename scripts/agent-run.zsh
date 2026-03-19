#!/bin/zsh
set -euo pipefail

# Ensure machine-local agent env vars are available.
if [ -f "$HOME/.opencode-agent-env" ]; then
  . "$HOME/.opencode-agent-env"
fi

# Ensure mise activation is available even in non-interactive contexts.
if [ -x "$HOME/.local/bin/mise" ]; then
  unset __MISE_ORIG_PATH MISE_SHELL __MISE_WATCH
  eval "$("$HOME/.local/bin/mise" env -s zsh)"
fi

if [ "$#" -lt 1 ]; then
  echo "Usage: ./scripts/agent-run.zsh '<command>'"
  exit 1
fi

exec /bin/zsh -lc "$*"
