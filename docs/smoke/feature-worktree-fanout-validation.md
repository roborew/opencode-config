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

## API-driven fan-out (added with `worktree-manager` + `plugins/worktree.js`)

These scenarios must pass after the worktree-manager subagent and the in-process plugin are deployed. They confirm that orchestration never bypasses the `/experimental/worktree` API and that the GUI stays in sync.

11. Confirm `agents/worktree-manager.md` exists, is registered in `opencode.json` under `agent.worktree-manager`, and is allowed by `agents/orchestrate.md` `task:` allow-list (`worktree-manager: allow`).
12. Confirm `plugins/worktree.js` is copied into `${OPENCODE_CONFIG_DIR}/plugins/` by the entrypoint, registers exactly four tools (`worktree_create`, `worktree_list`, `worktree_delete`, `worktree_reset`), and the opencode-server log shows `worktree plugin loaded` on boot.
13. From a fresh `orchestrate` session, dispatch a `worktree-manager` Task with `action: "create_feature"`, `slug: "<test>"`, `base: "develop"`. Expect the branch `opencode/feat-<test>` to appear in `git branch -a` inside the worktree directory and the worktree to appear in the Desktop GUI.
14. Dispatch `action: "create_ticket"`, `issue: <n>`, `slug: "<child>"`, `base: "opencode/feat-<test>"`. Expect `opencode/ticket-<n>-<child>` with `merge-base origin/opencode/feat-<test>` as an ancestor. Confirm the ticket branch is **not** `ticket/...` (the forbidden raw-git shape).
15. **API failure path:** stop the upstream `opencode serve` and dispatch any worktree action. Expect `worktree-manager` to return `blocker_code: WORKTREE_API_FAILED` with `manualRecovery` curl snippet. Expect the orchestrator to stop and **not** fall back to raw `git worktree` — no `git worktree add` lines should appear in any child transcript.
15a. **Dead upstream:** stop `opencode serve`, dispatch any worktree action. Expect `BLOCKED: WORKTREE_API_FAILED`, no `git worktree` fallback.
15b. **WorktreeNotGitError recovery:** simulate a context-less delete (or use the pre-fix plugin), dispatch `action: "delete"`. Expect `worktree-manager` to auto-recover via the sanctioned script + session deregister, returning `{ ok: true, recovered: true }`. Confirm the worktree is gone from `worktree_list`, `git worktree list`, and the GUI.
16. **Restart-reset path:** dispatch `action: "reset"`, `directory: "<ticket dir>"` after a simulated server restart. Confirm the worktree re-appears in the Desktop GUI session list within one poll cycle.
17. **Desktop UI smoke:** with one ticket worktree live, open the Desktop UI, confirm the worktree entry shows the session attached and the branch label renders `opencode/ticket-<n>-<child>` (not `ticket/<n>-<child>`).
18. **Self-guard on `OPENCODE_APPS_DIR`:** dispatch `action: "delete"`, `directory: "<anything under OPENCODE_APPS_DIR>"`. Expect `refused: PROTECTED_PROJECT_ROOT` from the plugin and the orchestrator to abort, not retry. Confirm no row was removed from `git worktree list` on the host.
19. **Hard-rule denial:** confirm `worktree-manager` cannot be invoked directly with `write: true` / `edit: true` (its frontmatter denies both) and that any bash attempt to run `rm -rf /`, `git push --force`, `git checkout -b <branch>`, or `git switch -c <branch>` is denied by its permission allow-list.
20. **One-shot contract:** confirm a single `worktree-manager` invocation handles exactly one action and that the orchestrator must re-dispatch for each lifecycle event (no batching inside the subagent).
21. **Recover action:** dispatch `action: "recover"`, `directory: "<stuck worktree dir>"` on an already-stuck worktree (one that failed a delete and still shows in `worktree_list`). Expect the sanctioned cleanup script (`rewrite-worktree-gitdirs.py remove/prune/scrub`) to run, orphan sessions to be deregistered via `DELETE /session/<id>`, and a re-list to confirm the worktree is gone from `worktree_list`, `git worktree list`, and the GUI.