---
name: orchestrate-develop-loop
description: "Develop-branch orchestrator loop: create feature worktree, dispatch bounded full-ticket Tasks in DAG-respecting batches, merge sub-PRs on human approval, delete ticket worktrees + remote branches, and hand off to feature-architect when all tickets land."
modelTier: "fast"
roleReminder: "Load only when `ORCHESTRATE_DEVELOP_LOOP` is unset or `1` and the bootstrap menu selected a feature backlog. Develop orchestrator lives in `develop` and is the ONLY branch-switching / worktree-* actor."
---

> Hard Rules live in `agents/orchestrate.md`; this skill owns the **per-impl-repo develop-loop** body. Routing kernel still lives in `orchestrate-execution`.

## Scope

Run the **develop** branch as the single persistent orchestration session for one `(feature:<slug>, impl-repo)` pair. From `develop`, create the feature worktree, then dispatch **one bounded full-ticket Task per ticket** (`execution_mode: github_issue_full`) in DAG-respecting batches. Each ticket session owns its own stages, sub-PR, and PR stabilization. The develop loop only reacts to the terminal ticket report (`READY_FOR_HUMAN_REVIEW` | `BLOCKED`). When all tickets merge into the feature branch, hand off to `architect-feature-signoff`.

The develop orchestrator does **not** load `orchestrate-verification` on the happy path; ticket-mode per-stage code-review runs *inside* the bounded Task.

## Entry conditions

- `agents/orchestrate.md` permission block includes `orchestrate-develop-loop` and `ticket-lifecycle` in the `skill:` allow object — otherwise loading fails with `SKILL_UNAVAILABLE`.
- `ORCHESTRATE_DEVELOP_LOOP` is unset or `1` (set `0` to force the legacy `github-issue-run` path for one release).
- Bootstrap finished; the user picked a `feature:<slug>` from the menu.
- `opencode-run impl orchestrate-readiness-check <slug>` returned PASS (non-empty `stages[]` on every open ticket).
- `checkout_contract` captured from `checkout-contract.sh` (`develop` branch is expected; protected branch confirmed).

## Procedure

### 1. Readiness + one-shot consent

1. Confirm readiness gate passed; record `readiness_status: PASS` in the lifecycle log.
2. Ask the user exactly once, record the answer as `auto_spawn_consent`:

   ```text
   Auto-spawn all runnable tickets for <slug> and only stop for human PR review? (yes/no)
   ```

   - **yes** → set `auto_spawn: true`. The loop dispatches every DAG-respecting ticket without further prompts; the only human gate is per-PR approval.
   - **no** → fall back to per-batch auto-vs-manual scheduling (legacy `feature-worktree/SKILL.md` behavior) for this run.

### 2. Feature worktree + push

Dispatch `worktree-manager` `create_feature`:

```json
{ "action": "create_feature", "slug": "<slug>", "base": "develop" }
```

On success, record `{ name: "feat-<slug>", branch: "opencode/feat-<slug>", directory }` in the lifecycle log. Push the feature branch from the develop orchestrator's own checkout via a delegated `developer` Task (`load: minimal`, `git push -u origin opencode/feat-<slug>`). The plugin does not push.

If `worktree-manager` returns any `blocker_code`, surface it verbatim and stop.

### 3. Loop (silent except the single PR-review gate)

```text
while true:
  batch_json=$(bash <OC>/skills/github-issue-run/lib/dev-loop-batch.sh <slug>)
  if batch is empty: break

  for entry in batch:
    ticket = entry.number
    title  = entry.title
    meta   = entry.opencode_meta

    # 3a. create ticket worktree
    dispatch worktree-manager create_ticket { issue, slug, base: opencode/feat-<slug>, title, auto_spawn: true }
    record { directory, branch: opencode/ticket-<n>-<slug>-<abbrev>, abbrev }

    # 3b. state transition
    delegated developer: bash <OC>/skills/github-issue-run/lib/issue-state-transition.sh <repo> <n> state:in-progress
      (set OPENCODE_EXPECT_REPO_ROOT + OPENCODE_EXPECT_BRANCH=<abbrev-branch> first)

    # 3c. dispatch bounded full-ticket Task
    Task <implementer> execution_mode: github_issue_full, load: full, with HANDOFF_TO_TICKET_SESSION marker
        passing: impl_repo_path, expected_branch (opencode/ticket-...-abbrev), is_linked_worktree: true,
                 main_checkout_root, branch_policy, worktree_directory, feature_branch, abbrev,
                 issue_number, repo, opencode_meta, auto_spawn_consent

  # 3d. wait for terminal reports (one per ticket in batch)
  # develop orchestrator blocks here; ticket sessions run autonomously to READY_FOR_HUMAN_REVIEW | BLOCKED.

  for each READY_FOR_HUMAN_REVIEW { pr_url, ci_evidence, comment_resolutions }:
    notify user: "PR ready for review: <pr_url>"   # ONLY HUMAN GATE
    wait for user: "yes, happy with that ticket" (or user has already merged)

    # 3e. merge sub-PR into opencode/feat-<slug> if not already merged
    delegated developer: gh pr merge <pr_url> --squash --delete-branch=false (or --merge per repo policy)
      on failure: surface mergeable/branch-protection error verbatim, pause batch
      on success: continue

    # 3f. fetch + fast-forward feature branch in the worktree
    delegated developer (cd <feature worktree directory>):
      git fetch origin opencode/feat-<slug>
      git merge --ff-only origin/opencode/feat-<slug>

    # 3g. delete the ticket worktree
    dispatch worktree-manager delete { directory: <ticket worktree dir> }

    # 3h. delete the remote ticket branch
    delegated developer: git push origin --delete opencode/ticket-<n>-<slug>-<abbrev>
      (developer is the only delegated actor for `git push origin --delete`; ticket session itself never runs this)

  for any BLOCKED ticket:
    surface the blocker + partial evidence verbatim
    await user; do not auto-advance
```

`auto_spawn_consent: true` means the loop never pauses for `ready to spawn next batch?` prompts; the only pause is at `READY_FOR_HUMAN_REVIEW`. `auto_spawn_consent: false` falls back to asking per batch (current `feature-worktree` behavior).

### 4. State transitions inside the loop

The bounded ticket Task owns `state:in-progress` (set before dispatch) and `state:ready-for-review` (set when the sub-PR opens). The develop orchestrator owns any subsequent state changes (`state:blocked` on `BLOCKED`, etc.). All transitions go through `issue-state-transition.sh <repo> <n> <state>` delegated to `developer`.

### 5. Failure handling

| Failure | Where it surfaces | Response |
|---|---|---|
| `worktree-manager` returns `blocker_code` | develop orchestrator loop | Surface verbatim, stop, do not retry. |
| `dev-loop-batch.sh` exits 1 | develop orchestrator loop | All tickets done → exit loop, go to step 6. |
| Ticket `BLOCKED: ENV_BLOCKED` after one repair | ticket session → develop orchestrator | Surface `recommended_env_fix`, pause batch. |
| Ticket `BLOCKED: STABILIZATION_EXHAUSTED` (CI fail after 3 iterations) | ticket session | Surface verbatim, pause batch. |
| Ticket `BLOCKED: CROSS_TICKET_REVIEW` | ticket session | Hand off to `architect-feature-signoff` immediately (skip step 6). |
| Sub-PR merge fails (branch protection / conflict) | develop orchestrator | Surface `gh pr view --json mergeable`, pause batch. |
| Remote-branch delete fails (protected / already gone) | develop orchestrator cleanup | Non-fatal: log, continue. Surface as advisory at feature close. |
| User merges sub-PR themselves | develop orchestrator | `gh pr view --json state` confirms MERGED; proceed to worktree + remote-branch cleanup. |
| User says "happy" but PR not yet merged | develop orchestrator | Orchestrator merges the sub-PR (delegated developer), then cleanup. |

### 6. Hand off to feature-architect

When `dev-loop-batch.sh` exits 1 and there are no `BLOCKED` tickets, **all** tickets have been merged into `opencode/feat-<slug>`. The develop orchestrator emits exactly:

```text
HANDOFF_TO_FEATURE_ARCHITECT: {
  "feature": "feature:<slug>",
  "feature_worktree_directory": "<abs path>",
  "feature_branch": "opencode/feat-<slug>",
  "next_agent": "architect",
  "next_skill": "architect-feature-signoff",
  "next_session_workdir": "<feature worktree dir>",
  "summary_table": [
    { "ticket": <n>, "title": <t>, "pr_url": <u>, "merged_at": <iso> }
  ],
  "implementation_repo": "<OWNER/REPO>",
  "impl_repo_path": "<abs path>"
}
```

and pauses. The user (or the spec session) starts the **feature-architect session** inside the feature worktree, where `architect-feature-signoff` takes over: full audit, feature-mode code-review, one-shot CodeRabbit (medium/hard), `pr_stabilization`, `feature-finish-pr.sh`, accept (`state:done`), merge with user confirmation, Phase R remediation if acceptance is unmet.

### 7. Close-loop resume

After the feature-architect merges the feature PR, the develop orchestrator resumes:

1. Delegated `developer`: `git push origin --delete opencode/feat-<slug>`.
2. Dispatch `worktree-manager` `delete { directory: <feature worktree dir> }`.
3. Delegated `developer` (in main checkout): `git fetch && git pull --ff-only origin develop`.
4. Emit one of:
   - `feature:<slug> complete; ready for spec close` (no more features queued), or
   - `feature:<slug> complete; ready for next feature` (loop continues).

## Hard rules for the develop orchestrator

- Never call `worktree_*` tools directly — delegate to `worktree-manager`.
- Never run `git push origin --delete` from the develop orchestrator session itself — delegate to a `developer` Task. This is the only branch-deleting actor.
- Never load `orchestrate-verification` for ticket-mode work — ticket sessions self-dispatch `code-review` inside `ticket-lifecycle`.
- Never modify a remote ticket branch (`opencode/ticket-...`) except to delete it after its sub-PR merges.
- Children never create, switch, checkout, or rename branches (Hard Rule §82). The develop orchestrator is the only branch-switching actor.
- The develop orchestrator never edits code or commits itself.

## See also

- `ticket-lifecycle` — the bounded full-ticket Task contract.
- `architect-feature-signoff` — the post-merge feature audit + sign-off owner.
- `feature-worktree` — worktree-creation JSON shapes + naming conventions still apply.
- `agents/worktree-manager.md` — `create_ticket` now derives `<abbrev>` and echoes `auto_spawn`.