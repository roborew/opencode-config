# shellcheck shell=bash
# Fetch docs/prd/<slug>.md from a linked spec repo (local checkout or GitHub ref).
# Usage: source fetch_spec_prd.sh; fetch_spec_prd_markdown <owner/repo> <slug> [issue-tracker.md]
# Sets FETCH_SPEC_PRD_REF and FETCH_SPEC_PRD_SOURCE on success; prints body to stdout.

_fetch_spec_prd_lib_dir() {
  (cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
}

if ! declare -F read_spec_repo_from_file >/dev/null 2>&1; then
  # shellcheck source=read_spec_repo.sh disable=SC1091
  source "$(_fetch_spec_prd_lib_dir)/read_spec_repo.sh"
fi

FETCH_SPEC_PRD_REF=""
FETCH_SPEC_PRD_SOURCE=""

read_spec_prd_ref_from_file() {
  local file="${1:-docs/agents/issue-tracker.md}"
  [[ -f "$file" ]] || return 1

  local line
  line=$(grep -iE '(SPEC_PRD_REF|PRD_REF|spec_prd_ref)[[:space:]]*:' "$file" | head -1) || return 1
  [[ -n "$line" ]] || return 1

  line=$(sed -E 's/.*(SPEC_PRD_REF|PRD_REF|spec_prd_ref)[[:space:]]*:[[:space:]]*//I' <<<"$line")
  line=$(sed -E 's/^[[:space:]]*\**//' <<<"$line")
  line=$(tr -d '\r`<>' <<<"$line")
  line=$(sed -E 's/[[:space:]]+$//' <<<"$line")
  line=$(sed -E 's/\*+$//' <<<"$line")
  line=$(sed -E 's/^[[:space:]]+|[[:space:]]+$//g' <<<"$line")

  [[ -z "$line" || "$line" == "__SPEC_PRD_REF__" ]] && return 1
  printf '%s\n' "$line"
}

fetch_spec_prd_markdown() {
  local spec_repo="$1" slug="$2" tracker="${3:-docs/agents/issue-tracker.md}"
  local relpath="docs/prd/${slug}.md"
  local sibling="../${spec_repo##*/}"
  local local_path="${sibling}/${relpath}"

  FETCH_SPEC_PRD_REF=""
  FETCH_SPEC_PRD_SOURCE=""

  if [[ -f "$local_path" ]]; then
    FETCH_SPEC_PRD_SOURCE="local:${local_path}"
    if [[ -d "${sibling}/.git" ]]; then
      FETCH_SPEC_PRD_REF="$(git -C "$sibling" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    fi
    cat "$local_path"
    return 0
  fi

  local configured="" sibling_ref="" ref=""
  configured=$(read_spec_prd_ref_from_file "$tracker" 2>/dev/null || true)
  if [[ -d "${sibling}/.git" ]]; then
    sibling_ref=$(git -C "$sibling" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  fi
  if [[ -n "$configured" ]]; then
    ref="$configured"
  elif [[ -n "$sibling_ref" ]]; then
    ref="$sibling_ref"
  fi

  local api_path="repos/${spec_repo}/contents/${relpath}"
  local -a tried=()

  _fetch_spec_prd_tried_ref() {
    local r="$1"
    [[ -z "$r" ]] && return 1
    local t
    for t in "${tried[@]}"; do
      [[ "$t" == "$r" ]] && return 1
    done
    tried+=("$r")

    local out=""
    if ! out=$(gh api "${api_path}?ref=${r}" --jq .content 2>/dev/null); then
      return 1
    fi
    [[ -n "$out" && "$out" != "null" ]] || return 1

    FETCH_SPEC_PRD_REF="$r"
    FETCH_SPEC_PRD_SOURCE="github:${spec_repo}@${r}"
    echo "$out" | base64 -d
    return 0
  }

  if _fetch_spec_prd_tried_ref "$ref"; then
    return 0
  fi

  local out="" default_ref=""
  if out=$(gh api "$api_path" --jq .content 2>/dev/null) && [[ -n "$out" && "$out" != "null" ]]; then
    default_ref=$(gh repo view "$spec_repo" --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || echo "unknown")
    FETCH_SPEC_PRD_REF="$default_ref"
    FETCH_SPEC_PRD_SOURCE="github:${spec_repo}@${default_ref}"
    echo "$out" | base64 -d
    return 0
  fi

  local fallback
  for fallback in develop main; do
    if _fetch_spec_prd_tried_ref "$fallback"; then
      return 0
    fi
  done

  return 1
}

parent_prd_url_from_text() {
  local text="$1"
  grep -oE 'Parent PRD:[[:space:]]*https://github\.com/[^[:space:]]+' <<<"$text" 2>/dev/null \
    | head -1 | sed -E 's/^Parent PRD:[[:space:]]*//' || true
}
