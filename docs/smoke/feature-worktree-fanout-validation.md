# Feature Worktree Fan-Out Validation

Run these scenarios against the primary opencode-server deployment before relying on feature fan-out in production:

1. Confirm the worktree plugin exposes `worktree_create` and `worktree_delete` inside the server session.
2. Restart the server and confirm worktree paths and `.git/worktrees` metadata survive.
3. Create `feature/<slug>` from `develop`, then create a child with `baseBranch=feature/<slug>`.
4. Confirm child sessions stream output to connected clients.
5. Confirm independent tickets share a manual batch while dependent tickets wait for merge and feature fast-forward.
6. Confirm sub-PRs use `feature/<slug>` as their exact base.
7. Disable the plugin and confirm exact manual worktree commands are printed and orchestration pauses.
8. Confirm `worktree_delete` refuses unmerged or unpushed work.
9. Confirm feature-mode code-review runs regression, integration, and e2e checks through the documented Docker/Sysbox path.
10. Introduce a sign-off defect and confirm it creates a new remediation ticket and child worktree rather than reopening a merged ticket.
