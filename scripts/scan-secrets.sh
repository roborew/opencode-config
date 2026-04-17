#!/usr/bin/env bash
# Scans stdin or file content for accidental secrets (pre-commit / manual).
# Usage: scan-secrets.sh [file]   (defaults to stdin)
# Exit 1 if patterns match; 0 if clean.

set -euo pipefail

CONTENT=""
if [[ -n "${1:-}" ]]; then
  CONTENT=$(cat "$1")
else
  CONTENT=$(cat)
fi

[[ -z "$CONTENT" ]] && exit 0

MATCHES=()

if echo "$CONTENT" | grep -qE 'AKIA[0-9A-Z]{16}'; then
  MATCHES+=("AWS access key (AKIA…)")
fi
if echo "$CONTENT" | grep -qiE '(aws_secret_access_key|secret_key)[[:space:]]*[=:][[:space:]]*["'\'']?[A-Za-z0-9/+=]{40}'; then
  MATCHES+=("AWS secret key pattern")
fi
if echo "$CONTENT" | grep -qE '(ghp_|gho_|ghs_|ghr_|github_pat_)[a-zA-Z0-9_]{20,}'; then
  MATCHES+=("GitHub token")
fi
if echo "$CONTENT" | grep -qE 'sk-[a-zA-Z0-9]{20,}'; then
  MATCHES+=("sk-… API key pattern")
fi
if echo "$CONTENT" | grep -qE 'xox[bpras]-[0-9a-zA-Z-]{10,}'; then
  MATCHES+=("Slack token")
fi
if echo "$CONTENT" | grep -qE -- '-----BEGIN[[:space:]]+(RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----'; then
  MATCHES+=("private key block")
fi
if echo "$CONTENT" | grep -qE '(mongodb|postgres|mysql|redis|amqp|smtp)(\+[a-z]+)?://[^:[:space:]]+:[^@[:space:]]+@'; then
  MATCHES+=("connection string with credentials")
fi

if [[ ${#MATCHES[@]} -gt 0 ]]; then
  echo "Possible secrets detected:" >&2
  for m in "${MATCHES[@]}"; do echo "  - $m" >&2; done
  exit 1
fi
exit 0
