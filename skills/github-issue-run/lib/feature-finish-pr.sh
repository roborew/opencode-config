#!/usr/bin/env bash
# Push the current branch and open (or reuse) a ready-for-review PR for feature:<slug>.
# Usage: feature-finish-pr.sh <feature_slug_without_prefix> [base_branch]
# Opt-out: ORCHESTRATE_AUTO_PR=0
# Base override: PR_BASE env, else $2, else develop (fallback to repo default if missing on origin).
set -euo pipefail

SLUG="${1:?feature slug required}"
ARG_BASE="${2:-}"
FEAT="feature:${SLUG}"

OC="${OPENCODE_CONFIG:-$HOME/.config/opencode}"
# shellcheck source=../../../scripts/lib/shared.sh
source "${OC}/scripts/lib/shared.sh"

REPO=$(gh_current_repo)
BRANCH=$(git rev-parse --abbrev-ref HEAD)

emit() {
  jq -nc \
    --arg branch "$BRANCH" \
    --arg base "$BASE" \
    --arg pr_url "${PR_URL:-}" \
    --argjson pr_number "${PR_NUMBER:-null}" \
    --arg action "$ACTION" \
    --arg repo "$REPO" \
    --arg message "${MESSAGE:-}" \
    '{branch: $branch, base: $base, pr_url: $pr_url, pr_number: $pr_number, action: $action, repo: $repo, message: $message}'
}

if [[ "${ORCHESTRATE_AUTO_PR:-1}" == "0" ]]; then
  ACTION="skipped-opt-out"
  BASE="${PR_BASE:-${ARG_BASE:-develop}}"
  MESSAGE="ORCHESTRATE_AUTO_PR=0; push and PR skipped."
  emit
  exit 0
fi

PROTECTED=(develop main master)
for p in "${PROTECTED[@]}"; do
  if [[ "$BRANCH" == "$p" ]]; then
    ACTION="skipped-protected-branch"
    BASE="${PR_BASE:-${ARG_BASE:-develop}}"
    MESSAGE="Refusing push/PR on protected branch '${BRANCH}'. Create a feature branch or worktree session, then re-run or use the ship skill."
    emit
    exit 0
  fi
done

BASE="${PR_BASE:-${ARG_BASE:-develop}}"
if ! git ls-remote --exit-code --heads origin "$BASE" >/dev/null 2>&1; then
  BASE=$(gh repo view "$REPO" --json defaultBranchRef -q .defaultBranchRef.name)
fi

git push -u origin "$BRANCH"

EXISTING=$(gh pr list --repo "$REPO" --head "$BRANCH" --base "$BASE" --state open --json number,url -q '.[0]' 2>/dev/null || echo null)
if [[ "$EXISTING" != "null" && -n "$EXISTING" ]]; then
  PR_URL=$(echo "$EXISTING" | jq -r .url)
  PR_NUMBER=$(echo "$EXISTING" | jq -r .number)
  ACTION="pr-exists"
  MESSAGE="Reused existing open PR."
  emit
  exit 0
fi

ISSUE_LINES=$(gh issue list --repo "$REPO" --label "$FEAT" --state all --limit 100 \
  --json number,title,state \
  -q '.[] | "- #\(.number) [\(.state)] \(.title)"' 2>/dev/null || true)
if [[ -z "$ISSUE_LINES" ]]; then
  ISSUE_LINES="- (no issues found with label ${FEAT})"
fi

PR_BODY=$(cat <<EOF
Automated PR for \`${FEAT}\`.

## Issues

${ISSUE_LINES}

---
Opened by \`feature-finish-pr.sh\` when the orchestrate queue for this feature was exhausted.
EOF
)

PR_TITLE="feat(${SLUG}): ${SLUG}"
PR_URL=$(gh pr create --repo "$REPO" \
  --base "$BASE" \
  --head "$BRANCH" \
  --title "$PR_TITLE" \
  --body "$PR_BODY")
PR_NUMBER=$(gh pr view "$PR_URL" --repo "$REPO" --json number -q .number)
ACTION="pr-created"
MESSAGE="Created ready-for-review PR."
emit
