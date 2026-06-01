#!/usr/bin/env bash
# Tests for read_spec_repo.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=read_spec_repo.sh disable=SC1091
source "${ROOT}/bin/lib/read_spec_repo.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $name — expected '$expected', got '$actual'" >&2
    exit 1
  fi
  echo "ok: $name"
}

assert_fail() {
  local name="$1"
  local file="$2"
  if read_spec_repo_from_file "$file" 2>/dev/null; then
    echo "FAIL: $name — expected failure, got success" >&2
    exit 1
  fi
  echo "ok: $name"
}

write_tracker() {
  local file="$tmpdir/issue-tracker.md"
  printf '%s\n' "$1" >"$file"
  printf '%s' "$file"
}

f=$(write_tracker '- SPEC_REPO: roborew/blocshed-spec')
assert_eq 'list plain' 'roborew/blocshed-spec' "$(read_spec_repo_from_file "$f")"

f=$(write_tracker '- **SPEC_REPO:** roborew/blocshed-spec')
assert_eq 'list bold' 'roborew/blocshed-spec' "$(read_spec_repo_from_file "$f")"

f=$(write_tracker 'SPEC_REPO: plain/value')
assert_eq 'bare line' 'plain/value' "$(read_spec_repo_from_file "$f")"

f=$(write_tracker '- **SPEC_REPO:** <owner>/<app>-spec>')
assert_fail 'placeholder rejected' "$f"

assert_fail 'missing file' "$tmpdir/missing.md"

echo "All read_spec_repo tests passed."
