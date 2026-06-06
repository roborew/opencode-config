#!/bin/zsh
set -euo pipefail

# Ensure machine-local agent env vars are available.
if [ -f "$HOME/.opencode-agent-env" ]; then
  . "$HOME/.opencode-agent-env"
fi

# Ensure mise activation is available even in non-interactive contexts.
mise_bin=""
for candidate in \
  "$HOME/.local/bin/mise" \
  "/opt/homebrew/bin/mise" \
  "/usr/local/bin/mise"; do
  if [ -x "$candidate" ]; then
    mise_bin="$candidate"
    break
  fi
done
if [ -z "$mise_bin" ] && command -v mise >/dev/null 2>&1; then
  mise_bin="$(command -v mise)"
fi
if [ -n "$mise_bin" ]; then
  unset __MISE_ORIG_PATH MISE_SHELL __MISE_WATCH
  eval "$("$mise_bin" env -s zsh)"
fi

if [ "$#" -lt 1 ]; then
  echo "Usage: ./scripts/agent-run.zsh '<command>'"
  exit 1
fi

exec /bin/zsh -lc "$*"
