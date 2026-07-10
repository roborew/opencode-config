#!/usr/bin/env bash
# Capture or verify the current git checkout/branch contract for orchestrate execution.
# Usage:
#   checkout-contract.sh              # emit JSON contract from cwd
#   checkout-contract.sh --verify     # exit 0 only if cwd matches OPENCODE_EXPECT_* env vars
# Env (verify mode):
#   OPENCODE_EXPECT_REPO_ROOT  absolute git toplevel
#   OPENCODE_EXPECT_BRANCH     branch name (required for --verify)
set -euo pipefail

MODE="${1:-}"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  jq -nc \
    --arg status "not_git" \
    --arg message "Not inside a git worktree" \
    '{status: $status, message: $message}'
  exit 1
fi

impl_repo_path="$(git rev-parse --show-toplevel)"
git_dir="$(git rev-parse --path-format=absolute --git-dir)"
git_common_dir="$(git rev-parse --path-format=absolute --git-common-dir)"
branch="$(git branch --show-current 2>/dev/null || true)"
head_sha="$(git rev-parse HEAD)"
upstream="$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null || echo "")"

is_linked="false"
main_checkout_root=""
if [[ "$git_dir" == *"/.git/worktrees/"* ]]; then
  is_linked="true"
  main_checkout_root="$(dirname "$git_common_dir")"
else
  main_checkout_root="$impl_repo_path"
fi

protected="false"
case "$branch" in
  develop|main|master) protected="true" ;;
esac

if [[ "$MODE" == "--verify" ]]; then
  expect_root="${OPENCODE_EXPECT_REPO_ROOT:-}"
  expect_branch="${OPENCODE_EXPECT_BRANCH:-}"
  if [[ -z "$expect_root" || -z "$expect_branch" ]]; then
    echo "checkout-contract: --verify requires OPENCODE_EXPECT_REPO_ROOT and OPENCODE_EXPECT_BRANCH" >&2
    exit 2
  fi
  if [[ "$impl_repo_path" != "$expect_root" ]]; then
    echo "CHECKOUT_CONTRACT_FAILED: repo root mismatch (expected $expect_root, got $impl_repo_path)" >&2
    exit 3
  fi
  if [[ "$branch" != "$expect_branch" ]]; then
    echo "CHECKOUT_CONTRACT_FAILED: branch mismatch (expected $expect_branch, got ${branch:-detached})" >&2
    exit 3
  fi
  exit 0
fi

jq -nc \
  --arg impl_repo_path "$impl_repo_path" \
  --arg git_dir "$git_dir" \
  --arg git_common_dir "$git_common_dir" \
  --argjson is_linked_worktree "$is_linked" \
  --arg main_checkout_root "$main_checkout_root" \
  --arg branch "$branch" \
  --arg head_sha "$head_sha" \
  --arg upstream "$upstream" \
  --argjson protected_branch "$protected" \
  --arg branch_policy "do not create, switch, checkout, or rename branches unless user explicitly requests in this turn" \
  '{
    status: "ok",
    impl_repo_path: $impl_repo_path,
    git_dir: $git_dir,
    git_common_dir: $git_common_dir,
    is_linked_worktree: $is_linked_worktree,
    main_checkout_root: $main_checkout_root,
    branch: $branch,
    head_sha: $head_sha,
    upstream: (if $upstream == "" then null else $upstream end),
    protected_branch: $protected_branch,
    branch_policy: $branch_policy
  }'
