#!/usr/bin/env bash
# Prevent concurrent fanout runs for the same slug (race → duplicate GitHub issues).

fanout_lock_acquire() {
  local slug="$1" root="$2"
  FANOUT_LOCK_DIR="${root}/.fanout-lock-${slug}"
  if ! mkdir "$FANOUT_LOCK_DIR" 2>/dev/null; then
    local holder=""
    if [[ -f "${FANOUT_LOCK_DIR}/pid" ]]; then
      holder=$(cat "${FANOUT_LOCK_DIR}/pid" 2>/dev/null || true)
    fi
    echo "fanout already running for '${slug}' (lock: ${FANOUT_LOCK_DIR}${holder:+, pid ${holder}})" >&2
    echo "Wait for the other run to finish. If stale, remove the lock directory and retry." >&2
    echo "Before any recovery: bin/fanout-audit ${slug} — never gh issue create until audit is clean." >&2
    exit 8
  fi
  echo "$$" >"${FANOUT_LOCK_DIR}/pid"
}

fanout_lock_release() {
  rm -rf "${FANOUT_LOCK_DIR:-}"
}
