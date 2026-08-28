---
name: feature-worktree
description: Coordinate feature and ticket worktrees with dependency-safe manual batches.
---

# Feature Worktree

Run inside the feature worktree session. For setup, call `worktree_create(branch="feature/<slug>", baseBranch="develop")`, push the branch, and record `baseBranch` in the checkout contract. Present auto versus manual scheduling once; default to manual batches.

Build the dependency DAG from each ticket's `depends_on`. Batch independent tickets, sequence dependent or overlapping-file tickets, and create each child with `worktree_create(branch="ticket/<issue>-<slug>", baseBranch="feature/<slug>")`. Run test-writer RED, the Owner GREEN stage, and code-review ticket mode in the child. Open sub-PRs with `head=ticket/<issue>-<slug>` and `base=feature/<slug>`.

After a child merges, call `worktree_delete(reason)` and in the feature worktree run `git fetch` followed by `git merge --ff-only origin/feature/<slug>` before dependent work. Never delete unmerged or unpushed work.

If plugin tools are unavailable or fail, stop and print:

```sh
git worktree add -b feature/<slug> ../feature-<slug> develop
git push -u origin feature/<slug>
```

Resume only after the user confirms the feature worktree exists. Never fall back to a branch-only parent.
