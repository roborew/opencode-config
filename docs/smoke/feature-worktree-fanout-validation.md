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

## Develop-loop branch shape + auto-spawn + bounded Task (added with `orchestrate-develop-loop` + `ticket-lifecycle`)

These scenarios confirm the new develop-branch orchestrator and bounded full-ticket Task path. They run after the API-driven fan-out scenarios above and depend on them.

22. **Naming with `<abbrev>`.** Dry-run a feature with 5 tickets. Verify `git branch -r | grep opencode/` returns `feat-<slug>` + exactly 5 `ticket-<issue>-<slug>-<abbrev>` branches. Each `<abbrev>` is 3–6 kebab-case words derived from the issue title (lowercase, stopwords dropped, `-2/-3` appended only on collision). Confirm `<abbrev>` is **not** the full title and never contains slashes or uppercase.
23. **`auto_spawn` echo.** Dispatch `worktree-manager` `create_ticket` with `{ issue, slug, base, title, auto_spawn: true }`. Confirm the JSON response includes `auto_spawn: true` echoed back and `abbrev` set to the derived `<abbrev>`. Confirm the ticket branch matches `opencode/ticket-<issue>-<slug>-<abbrev>` exactly (no extra suffixes).
24. **Abbrev collision.** With two issues whose titles produce the same `<abbrev>`, dispatch two `create_ticket` calls. Expect the first to land on `opencode/ticket-<issue1>-<slug>-<abbrev>` and the second on `opencode/ticket-<issue2>-<slug>-<abbrev>-2`. Confirm `-3` on a third collision and `BLOCKED: WORKTREE_NAME_COLLISION` after `-9`.
25. **`dev-loop-batch.sh` DAG.** Pre-create 4 issues: A (no deps), B (no deps), C (Blocked by A), D (Blocked by B). Confirm the script returns A + B in one call, then C + D after their blockers close.
26. **Bounded Task dispatch (no orchestrator between stages).** With `auto_spawn_consent: true`, dispatch a `developer` Task with `execution_mode: github_issue_full` for a 2-stage ticket. Capture the implementer's transcript; confirm it runs **both** stages, **two** `code-review` calls (one per stage), opens the sub-PR, runs `pr-stabilize-watch.sh`, and emits exactly one `READY_FOR_HUMAN_REVIEW` or `BLOCKED` report. Confirm the implementer post-completion guard does NOT fire between stages.
27. **Silent per-ticket preflight happy path.** In a ticket worktree with valid `.env`/Infisical, the ticket session runs `worktree-env` + `preflight` and produces no user prompt. Confirm via the ticket session's lifecycle log; confirm `preflight_skipped_on_protected_branch: true` in the develop orchestrator's bootstrap log.
28. **Silent per-ticket preflight block path.** Force a preflight failure that survives one repair pass (e.g. missing `.env` copy after `worktree-env`). Ticket session returns `BLOCKED: ENV_BLOCKED` with `recommended_env_fix`; develop orchestrator surfaces exactly one recommendation and pauses the batch — no auto-advance.
29. **PR stabilization in ticket session.** With a CI failure on the sub-PR that can be fixed in-worktree (TDD), confirm the ticket session fixes, commits `Refs: #<n>`, pushes, and re-runs `pr-stabilize-watch.sh`. Loop bounded at 3 iterations; on exhaustion, confirm `BLOCKED: STABILIZATION_EXHAUSTED` is returned to the develop orchestrator.
30. **Cross-ticket review escalation.** Inject a review comment whose fix would touch files in a different ticket's branch. Confirm the ticket session returns `BLOCKED: CROSS_TICKET_REVIEW`; the develop orchestrator hands off to `architect-feature-signoff` early (skipping the wait-for-empty-batch exit).
31. **Single human gate.** With `auto_spawn_consent: true`, run a 3-ticket feature. Expect exactly 3 user notifications (one per sub-PR) and **zero** other prompts until the feature-architect session is started by the user.
32. **Remote-branch cleanup.** After each sub-PR merges, verify `git ls-remote origin` no longer lists `opencode/ticket-<issue>-<slug>-<abbrev>`. Orphan-remote-branch count = 0 mid-feature.
33. **Feature-architect handoff.** After all tickets merge into `opencode/feat-<slug>`, confirm the develop orchestrator emits `HANDOFF_TO_FEATURE_ARCHITECT` with the summary table and pauses. Confirm the new architect session (running `architect-feature-signoff`) runs in the feature worktree and never touches `develop` or any ticket branch.
34. **Close-loop.** After `architect-feature-signoff` merges the feature PR, the develop orchestrator resumes: `git push origin --delete opencode/feat-<slug>` succeeds, `worktree-manager delete` succeeds, `git -C <impl-root> pull --ff-only origin develop` succeeds. Print `feature:<slug> complete; ready for spec close`.
35. **Worktree + remote-branch ownership.** Confirm no ticket-session transcript contains `git push origin --delete` or any `worktree_*` tool call. Confirm the develop orchestrator never runs `git push origin --delete` itself — it always delegates to a `developer` Task with `load: minimal`.
36. **Skill allowlist.** Confirm `agents/orchestrate.md` `skill:` allow object includes `orchestrate-develop-loop`, `ticket-lifecycle`, and `architect-feature-signoff`. Removing any of them causes a `SKILL_UNAVAILABLE` failure at load time.