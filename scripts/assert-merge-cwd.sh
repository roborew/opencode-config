#!/usr/bin/env bash
# assert-merge-cwd.sh — develop-pollution guard
#
# Sourced by a developer Task immediately before any `git merge` invocation.
# Enforces the develop-loop policy: feature code reaches `develop` ONLY via
# `gh pr merge` after the human "all reviewed" gate. Any direct `git merge`
# of an `origin/opencode/*` ref into `develop` is refused with a BLOCKED
# code on stderr.
#
# Required env vars (all must be set; unset/missing = script error):
#   ASSERT_MERGE_CWD          Absolute path the cwd MUST equal
#                             (`git rev-parse --show-toplevel`).
#   ASSERT_MERGE_BRANCH       Branch currently checked out (or HEAD branch
#                             of the worktree).
#   ASSERT_MERGE_REF          The ref passed to `git merge`
#                             (e.g. `origin/opencode/feat-foo`).
#   ASSERT_REPO               OWNER/REPO for `gh` lookups.
#   ASSERT_BRANCH_CONTEXT     One of:
#                               - `develop-main-checkout` (the orchestrator's
#                                 main checkout on `develop`)
#                               - `feature-worktree`      (opencode/feat-<slug>)
#                               - `ticket-worktree`       (opencode/ticket-<n>-...)
#
# Exit codes:
#   0  assertion passed — caller may proceed with `git merge`
#   1  assertion failed — stderr has BLOCKED: <reason> verbatim
#   2  misconfiguration  — missing required env var
#
# Behavior (fail-fast on first miss):
#   1. cwd top-level must equal ASSERT_MERGE_CWD
#      → BLOCKED: MERGE_CWD_MISMATCH expected=<p> actual=<p>
#   2. current branch must equal ASSERT_MERGE_BRANCH
#      → BLOCKED: MERGE_BRANCH_MISMATCH expected=<b> actual=<b>
#   3. STRICT develop mode: ASSERT_BRANCH_CONTEXT=develop-main-checkout AND
#      ASSERT_MERGE_REF matches ^origin/opencode/ → BLOCKED: DEVELOP_PROTECTED.
#      (Even --ff-only is rejected. Feature code reaches develop ONLY via
#      `gh pr merge` after the human "all reviewed" gate.)
#   4. If ASSERT_MERGE_REF matches ^origin/opencode/(feat|ticket)- AND a PR
#      exists with head=<ref-stripped> base=develop, route the caller to
#      `gh pr merge <url>` instead:
#      → BLOCKED: DEVELOP_MERGE_REQUIRES_PR pr=<url>
#      (Skipped in the self-ff carve-out: ASSERT_BRANCH_CONTEXT=feature-worktree
#       AND ASSERT_MERGE_REF == origin/<ASSERT_MERGE_BRANCH>.)
#   5. If ASSERT_MERGE_REF does not match ^origin/(develop|opencode/) →
#      BLOCKED: MERGE_REF_NOT_ALLOWED ref=<ref>.
#      (Arbitrary local paths, tags, or non-origin refs are refused.)
#
# On pass: emits `ASSERT_MERGE_OK cwd=<p> branch=<b> ref=<ref>` on stderr and
# returns 0. The caller then runs `git merge` itself.
#
# The script is READ-ONLY — it never invokes `git merge` or mutates state.
#
# Repro from the 2026-09-02 incident:
#   develop reflog:  fdfef0a develop@{2026-09-02 16:07:12 +0000}: merge
#                   origin/opencode/feat-workflow-runtime: Fast-forward
#   develop was at 5988249 (clean) before, f129800 (polluted) after.
#   This script's step 3 (DEVELOP_PROTECTED) is exactly the guard that would
#   have refused that merge in /home/robin/01_REPOS/apps/blocshed-web (develop
#   checkout) with the same args.

set -euo pipefail

die() {
  echo "BLOCKED: $1" >&2
  exit 1
}

# Required-env-var contract (misconfiguration = exit 2, distinct from policy = exit 1).
for v in ASSERT_MERGE_CWD ASSERT_MERGE_BRANCH ASSERT_MERGE_REF ASSERT_REPO ASSERT_BRANCH_CONTEXT; do
  if [[ -z "${!v:-}" ]]; then
    echo "assert-merge-cwd.sh: required env var '$v' is empty or unset" >&2
    exit 2
  fi
done

case "$ASSERT_BRANCH_CONTEXT" in
  develop-main-checkout|feature-worktree|ticket-worktree) ;;
  *)
    echo "assert-merge-cwd.sh: ASSERT_BRANCH_CONTEXT='$ASSERT_BRANCH_CONTEXT' is not one of develop-main-checkout|feature-worktree|ticket-worktree" >&2
    exit 2
    ;;
esac

# Step 1: cwd top-level match.
cwd_top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$cwd_top" ]]; then
  die "MERGE_CWD_UNRESOLVABLE cwd is not inside a git work tree"
fi
if [[ "$cwd_top" != "$ASSERT_MERGE_CWD" ]]; then
  die "MERGE_CWD_MISMATCH expected=${ASSERT_MERGE_CWD} actual=${cwd_top}"
fi

# Step 2: branch match.
current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [[ -z "$current_branch" ]]; then
  die "MERGE_BRANCH_UNRESOLVABLE HEAD is detached or unborn"
fi
if [[ "$current_branch" != "$ASSERT_MERGE_BRANCH" ]]; then
  die "MERGE_BRANCH_MISMATCH expected=${ASSERT_MERGE_BRANCH} actual=${current_branch}"
fi

# Step 5 first (cheapest) — only origin/develop and origin/opencode/* refs allowed.
if [[ ! "$ASSERT_MERGE_REF" =~ ^origin/(develop|opencode/) ]]; then
  die "MERGE_REF_NOT_ALLOWED ref=${ASSERT_MERGE_REF} (only origin/develop and origin/opencode/* are eligible)"
fi

# Step 3 — STRICT develop mode: refuse ALL `git merge origin/opencode/*` from
# the develop main checkout. Even --ff-only is rejected. Feature code reaches
# develop ONLY via `gh pr merge` after the human "all reviewed" gate.
if [[ "$ASSERT_BRANCH_CONTEXT" == "develop-main-checkout" \
      && "$ASSERT_MERGE_REF" =~ ^origin/opencode/ ]]; then
  die "DEVELOP_PROTECTED develop never accepts opencode/* refs via git merge; route through gh pr merge after the human 'all reviewed' gate"
fi

# Step 4 — self-ff carve-out. When the caller is in a feature worktree and
# merging the same branch's origin tip (e.g. `git merge --ff-only
# origin/opencode/feat-<slug>` to fast-forward the local feature branch in
# sync with remote), the PR check below is a no-op because the ref == branch
# being merged into is the same branch.
is_self_ff=0
if [[ "$ASSERT_BRANCH_CONTEXT" == "feature-worktree" \
      && "$ASSERT_MERGE_REF" == "origin/${ASSERT_MERGE_BRANCH}" ]]; then
  is_self_ff=1
fi

# Step 4 (PR-routing gate): if a PR exists with head=<ref-branch>, base=develop,
# force the caller to use `gh pr merge` instead of `git merge`. This catches the
# case where an agent has `git merge origin/opencode/feat-foo` ready but the
# feature branch already has an open or merged PR into develop — the only legal
# merge path is `gh pr merge <url>`.
if [[ "$is_self_ff" -eq 0 \
      && "$ASSERT_MERGE_REF" =~ ^origin/opencode/(feat|ticket)- ]]; then
  ref_branch="${ASSERT_MERGE_REF#origin/}"
  # Ticket refs carry a per-issue suffix (-<abbrev>[-N]); gh pr list --head
  # matches by exact head ref, so we use prefix match via the issue number
  # when ref_branch starts with `opencode/ticket-`.
  head_filter="$ref_branch"
  if [[ "$ref_branch" =~ ^opencode/ticket-([0-9]+)- ]]; then
    head_filter="opencode/ticket-${BASH_REMATCH[1]}-"
  fi
  pr_json="$(gh pr list --repo "$ASSERT_REPO" --state all \
              --head "$head_filter" --base develop \
              --json number,url,state,headRefName 2>/dev/null || echo '[]')"
  # When filtering by prefix (ticket case), narrow to an exact ref-branch match.
  matching_pr="$(printf '%s' "$pr_json" | jq -r --arg h "$ref_branch" \
    '[.[] | select(.headRefName == $h) | {number,url,state}] | .[0] // empty' 2>/dev/null || true)"
  if [[ -n "$matching_pr" ]]; then
    pr_url="$(printf '%s' "$matching_pr" | jq -r .url)"
    pr_state="$(printf '%s' "$matching_pr" | jq -r .state)"
    die "DEVELOP_MERGE_REQUIRES_PR pr=${pr_url} state=${pr_state}; a PR for ${ref_branch} → develop already exists; route through gh pr merge"
  fi
fi

echo "ASSERT_MERGE_OK cwd=${cwd_top} branch=${current_branch} ref=${ASSERT_MERGE_REF}" >&2
exit 0
