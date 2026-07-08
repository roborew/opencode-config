# shellcheck shell=bash
# Parse SPEC_REPO from docs/agents/issue-tracker.md (markdown list/bold tolerated).
# Usage: read_spec_repo_from_file [path]
read_spec_repo_from_file() {
  local file="${1:-docs/agents/issue-tracker.md}"
  [[ -f "$file" ]] || return 1

  local line
  line=$(grep -iE '(SPEC_REPO|spec_repo|Spec repo|spec repository)[[:space:]]*:' "$file" | head -1) || return 1
  [[ -n "$line" ]] || return 1

  line=$(sed -E 's/.*(SPEC_REPO|spec_repo|Spec repo|spec repository)[[:space:]]*:[[:space:]]*//I' <<<"$line")
  line=$(sed -E 's/^[[:space:]]*\**//' <<<"$line")
  line=$(tr -d '\r`' <<<"$line")
  line=$(sed -E 's/[[:space:]]+$//' <<<"$line")
  line=$(sed -E 's/\*+$//' <<<"$line")
  line=$(sed -E 's/^[[:space:]]+|[[:space:]]+$//g' <<<"$line")

  [[ "$line" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || return 1
  printf '%s\n' "$line"
}
