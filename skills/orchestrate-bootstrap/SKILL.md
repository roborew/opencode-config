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
4. **Branch-aware menu.** When no work source is supplied, present exactly one of two menus based on the checkout:

   **Menu A — protected branch (`develop` / `main` / `master`, `is_linked_worktree: false`):**

   ```text
   (1) Drive `feature:<slug>` from this develop branch? (develop-loop — recommended)
   (2) Build / refresh this branch in Sysbox sandbox? (compose build/test + optional review URL)
   (3) Hand back to `architect` for remediation loop? (impl option 4 → R)
   (4) Something else (debug, refactor, doc review, etc.) — describe the task; usually switch to `architect`
   ```

   For `(1)`, capture the kebab-case slug and load `orchestrate-develop-loop` (it calls `feature-worktree` internally for the worktree JSON shapes; the develop loop owns batch sizing, auto-spawn, and per-ticket Task dispatch). Run `opencode-run impl orchestrate-readiness-check <slug>` first; PASS requires non-empty `stages[]` and implementation planning on every open feature ticket. FAIL stops and returns to spec architect option 1.

   **Menu B — linked worktree (`is_linked_worktree: true`) or non-protected branch:**

   ```text
   (1) Continue this feature worktree's tickets? (uses feature-worktree directly)
   (2) Build / refresh this worktree in Sysbox sandbox? (compose build/test + optional review URL)
   (3) Hand back to `architect` for remediation loop? (impl option 4 → R)
   (4) Something else (debug, refactor, doc review, etc.) — describe the task; usually switch to `architect`
   ```

   For `(1)`, capture the slug from the existing branch (`opencode/feat-<slug>` or `opencode/ticket-<issue>-<slug>-<abbrev>`), load `feature-worktree`, run the readiness gate, and dispatch tickets via `next-runnable-issue.sh` (legacy path) or `dev-loop-batch.sh` (develop-loop path).

5. For `(2)` (either menu), load `orchestrate-sandbox`; do not enter the GitHub queue. For `(3)`, stop with the implementation architect Phase R handoff. For `(4)`, route to architect unless the message supplies an explicit queue or sandbox request.

## Environment State

Track `worktree_env_checked`, canonical `{wt_root, main_root, files[]}` evidence, `preflight_repair_attempted`, `sandbox_status`, `preflight_skipped_on_protected_branch`, and `auto_spawn_consent` (set by `orchestrate-develop-loop` on first prompt). Do not create an artifact for these values. One automatic repair pass is allowed; after a second identical report, stop with one `recommended_env_fix` and `LOOP_DETECTED` where applicable.