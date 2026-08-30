---
name: orchestrate-bootstrap
description: "Fresh-session bootstrap: checkout identity, branch-aware preflight, indexing readiness, work selection, and GitHub issue-expand readiness. Not for queue execution or recovery."
modelTier: "fast"
roleReminder: "Load before work selection; reload only when checkout identity changes."
---

> Hard Rules live in `agents/orchestrate.md`; this skill owns only startup gates and work selection. The preflight prompt is skipped on `develop` / `main` / `master` (no active feature worktree) because environment verification is now owned by the per-ticket session under the develop loop.

## Procedure

1. **Preflight gate (branch-aware).** Read `branch` from `checkout_contract` (run in step 2 if not yet captured):
   - If `branch ∈ {develop, main, master}` **and** no active feature worktree is selected → record `preflight_skipped_on_protected_branch: true` and **do not** prompt. Preflight is owned by the per-ticket session under `orchestrate-develop-loop` and runs silently there.
   - Otherwise (linked worktree / feature branch / ticket branch): if neither `env_gate_passed` nor `env_gate_declined` is recorded, ask exactly: `Run preflight now? (yes/no)`. On yes, Task `worktree-env` with `load: full`, then Task `preflight` with `load: full` using the repair-first flow. On no, record `env_gate_declined` and do not run preflight.
2. Always run checkout identity: Task `developer` with `load: minimal` to execute `skills/github-issue-run/lib/checkout-contract.sh`. Require `status: ok`, repo root, branch, worktree status, main checkout root, protected-branch status, head SHA, and branch policy. Stop on mismatch or protected branch before implementation/state mutation. Capture `is_linked_worktree` and `branch_policy` — the menu below uses them.
3. Run Claude Context readiness for the workspace path. If unavailable, record `MCP_FALLBACK`; discovery-heavy children must enforce their own readiness gate.
4. **Work-selection menu (branch-aware).** When no work source is supplied, present exactly one of two menus based on the checkout. Menus are **task-oriented** — they describe what the user wants to *do*, not which skill loads. Never surface lifecycle states or skill names as options.

   **Menu A — on a protected branch (`develop` / `main` / `master`, `is_linked_worktree: false`):** the user is starting fresh with no feature worktree yet. Sandbox is not offered here (there is no feature branch to build yet).

   ```text
   What do you want to do?

   (1) Start a new feature — give me the `feature:<slug>` and I'll create the feature worktree, then run every ticket end-to-end to a ready-for-review PR. (recommended)
   (2) Resume a feature — reattach to a feature or ticket worktree from a previous session and continue its queue.
   (3) Remediation loop — re-check PR feedback / CI after you pushed fixes (routes to architect option 4 → R).
   (4) Something else (debug, refactor, doc review) — describe the task; I'll usually route you to `architect`.
   ```

   For `(1)`, capture the kebab-case slug, run `opencode-run impl orchestrate-readiness-check <slug>` (PASS requires non-empty `stages[]` and implementation planning on every open feature ticket; FAIL stops and returns to spec architect option 1), then load `orchestrate-develop-loop`. The develop loop creates the feature worktree via `worktree-manager`, pushes `opencode/feat-<slug>`, and for each runnable ticket creates a ticket worktree with a `kickoff_message` (the plugin writes `<gitdir>/opencode-ticket-brief.json` and injects the message into the auto-started GUI session via `session.promptAsync` — that auto-started session IS the ticket session and loads `ticket-lifecycle`). **The user does not separately "create the worktree" — picking the feature slug is the single action that starts the whole process.**

   For `(2)`, Task `worktree-manager` `list` to discover existing worktrees; if one matches a `feature:<slug>`, capture that slug and load `orchestrate-develop-loop` (or `feature-worktree` on the legacy path) to continue. If no worktrees exist, tell the user and fall back to `(1)`.

   **Menu B — already inside a feature or ticket worktree (`is_linked_worktree: true`) or on a non-protected feature branch:** the user is mid-feature, so sandbox and ticket-continuation are both relevant.

   ```text
   What do you want to do?

   (1) Continue this feature's tickets — run the next runnable ticket(s) in this worktree.
   (2) Build / refresh this worktree in Sysbox sandbox — compose build/test + optional review URL.
   (3) Remediation loop — re-check PR feedback / CI after you pushed fixes (routes to architect option 4 → R).
   (4) Something else (debug, refactor, doc review) — describe the task; I'll usually route you to `architect`.
   ```

   For `(1)`, capture the slug from the existing branch (`opencode/feat-<slug>` or `opencode/ticket-<issue>-<slug>-<abbrev>`), run the readiness gate, then dispatch tickets via `dev-loop-batch.sh` (develop-loop path) or `next-runnable-issue.sh` (legacy path).

5. For `(2)` (Menu B only), load `orchestrate-sandbox`; do not enter the GitHub queue. For `(3)` (either menu), stop with the implementation architect Phase R handoff. For `(4)` (either menu), route to architect unless the message supplies an explicit queue or sandbox request.

## Environment State

Track `worktree_env_checked`, canonical `{wt_root, main_root, files[]}` evidence, `preflight_repair_attempted`, `sandbox_status`, `preflight_skipped_on_protected_branch`, and `auto_spawn_consent` (set by `orchestrate-develop-loop` on first prompt). Do not create an artifact for these values. One automatic repair pass is allowed; after a second identical report, stop with one `recommended_env_fix` and `LOOP_DETECTED` where applicable.