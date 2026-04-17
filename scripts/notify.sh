#!/usr/bin/env bash
# Native notification when the AI needs attention.
# Usage: notify.sh [message]

set -euo pipefail
MSG="${1:-OpenCode needs your attention}"

if command -v osascript >/dev/null 2>&1; then
  osascript -e "display notification \"$MSG\" with title \"OpenCode\""
elif command -v notify-send >/dev/null 2>&1; then
  notify-send "OpenCode" "$MSG"
else
  echo "$MSG"
fi
