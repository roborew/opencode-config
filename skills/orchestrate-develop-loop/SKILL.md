---
name: orchestrate-develop-loop
description: "Develop-branch orchestrator loop: create feature worktree, dispatch bounded full-ticket Tasks in DAG-respecting batches, merge sub-PRs on human approval, delete ticket worktrees + remote branches, and hand off to feature-architect when all tickets land."
modelTier: "fast"
roleReminder: "Load only when `ORCHESTRATE_DEVELOP_LOOP` is unset or `1` and the bootstrap menu selected a feature backlog. Develop orchestrator lives in `develop` and is the ONLY branch-switching / worktree-* actor."
---

> Hard Rules live in `agents/orchestrate.md`; this skill owns the **per-impl-repo develop-loop** body. Routing kernel still lives in `orchestrate-execution`.

## Scope

Run the **develop** branch as the single persistent orchestration session for one `(feature:<slug>, impl-repo)` pair. From `develop`, create the feature worktree, then **for each runnable ticket, create a ticket worktree + kick the auto-started GUI session** with a short pointer message (the ticket session itself loads `ticket-lifecycle`, reads the brief file the plugin wrote into the worktree gitdir, and reconstructs the rest from GitHub). The develop loop only reacts to terminal ticket reports (`READY_FOR_HUMAN_REVIEW` | `BLOCKED`) — posted as `ticket_report:` comments on the issue and best-effort injected back via `session_notify`. When all tickets merge into the feature branch, hand off to `architect-feature-signoff`.

The develop loop does **not** dispatch ticket subagents via the `task` tool. Subagents inherit the parent's cwd (`develop`), so they would land on the wrong branch and `checkout-contract.sh --verify` would correctly reject them (`SubtaskPartInput` in the installed SDK has no `directory` field). The auto-started GUI session for the ticket worktree IS the ticket session — it has the correct cwd by construction.

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
    abbrev = <derive from title or pass via entry if worktree-manager echoes it>
    branch_name = "opencode/ticket-<n>-<slug>-<abbrev>"

    # 3a. create ticket worktree + kick the auto-started GUI session
    kickoff_message = compose_kickoff_message(
        issue=entry, feature_slug=slug, branch=branch_name,
        worktree_dir=DIRECTORY_FROM_RESPONSE, brief_file=<gitdir>/opencode-ticket-brief.json)

    dispatch worktree-manager create_ticket {
      issue, slug, base: opencode/feat-<slug>, title,
      auto_spawn: true,
      kickoff_agent: matched implementer (developer | frontend-dev | ux-dev),
      kickoff_message,
    }

    record {
      directory, branch: opencode/ticket-<n>-<slug>-<abbrev>, abbrev,
      session_id, develop_session_id, kickoff (admitted|no_session_after_poll|failed)
    }

    if kickoff != admitted:
      # advisory only — brief file fallback stands.
      # The orchestrator may retry via worktree-manager `kickoff` action,
      # or the user may open the GUI session and type any message —
      # ticket-lifecycle §0 reads the brief file and reconstructs from GitHub.
      surface advisory in lifecycle log; do NOT pause the batch.
      # The poller/scripts/dev-loop-poller.sh + dev-loop-watch.sh will detect
      # the ticket_report: comment regardless of how the ticket was kicked.

  # 3b. (removed) state:in-progress is now set inside the ticket session itself
  #     via issue-state-transition.sh delegated to a developer Task whose cwd
  #     IS the ticket worktree (no OPENCODE_EXPECT_* dance). See ticket-lifecycle §0.

  # 3c. (removed) there is NO task-tool ticket dispatch. The auto-started GUI
  #     session IS the ticket session; it self-bootstraps from the brief file
  #     in its worktree gitdir (see ticket-lifecycle §0).

  # 3d. wait for terminal reports (one per ticket in batch)
  #     wakes come from: (i) session_notify terminal-report injection (primary),
  #                       (ii) poller scripts/dev-loop-poller.sh firing DEV_LOOP_WAKE,
  #                       (iii) any user message — run dev-loop-watch.sh first.
  # End the turn after batch kickoff; do not block.
```

#### 3a. Compose the kickoff message

The message is a short pointer — truncation-proof by design. The ticket session reconstructs the full payload from the brief file + GitHub.

```text
execution_mode: github_issue_full
issue: OWNER/REPO#<n> (<issue_url>)
feature: feature:<slug> (base branch opencode/feat-<slug>)
expected_branch: opencode/ticket-<n>-<slug>-<abbrev>
worktree: <abs path>
brief: <gitdir>/opencode-ticket-brief.json
Load skill ticket-lifecycle and begin. The GitHub issue body (opencode-task-yaml) is the source of truth for stages[], acceptance, and test commands. Do not ask for a pasted brief; reconstruct anything missing per ticket-lifecycle Bootstrap.
```

Compose it once per ticket; pass it verbatim to `worktree_create` as `kickoff_message`. The plugin writes the brief file and injects the message via `session.promptAsync`.

#### 3b. Resume behavior

- After kicking the batch, **end the turn**. Wakes (in priority order):
  1. **In-session `session_notify`** — when a ticket session posts its terminal report, the develop orchestrator receives an injected message and runs the PR-approval gate for that ticket.
  2. **Poller `DEV_LOOP_WAKE`** — `scripts/dev-loop-poller.sh` (server-host cron) detects `ticket_report:` comment deltas and wakes the develop orchestrator.
  3. **Any user message** — run `dev-loop-watch.sh` first, process deltas, then handle the message.
- Wake contract: incoming message begins with `DEV_LOOP_WAKE: { repo, feature, reason }` → run `dev-loop-watch.sh`; if no active loop for that feature is in the lifecycle log, ignore (idempotent — "ignore if not yours").

#### 3c. PR-approval gate

For each `READY_FOR_HUMAN_REVIEW` (received via `session_notify` or by parsing the latest `ticket_report:` comment from `dev-loop-watch.sh`):

```text
notify user: "PR ready for review: <pr_url>"   # ONLY HUMAN GATE
wait for user: "yes, happy with that ticket" (or user has already merged)
```

#### 3d. Merge + cleanup

After user approval reply:

1. **Merge the sub-PR** — delegated `developer` Task with **the exact worktree/repo directory and `cd`/`git -C` in the prompt** (fixes the inherited-cwd failures from the old task-tool dispatch path):

   ```text
   cd <feature worktree directory>
   gh pr merge <pr_url> --squash --delete-branch=false
   ```

   On failure: surface `gh pr view --json mergeable` verbatim, pause the batch. On success: continue.

2. **Fast-forward the feature branch** in the feature worktree (delegated `developer`, `cd <feature worktree dir>`):

   ```bash
   git fetch origin opencode/feat-<slug>
   git merge --ff-only origin/opencode/feat-<slug>
   ```

3. **Delete the ticket worktree** — dispatch `worktree-manager` `delete { directory: <ticket worktree dir> }`.

4. **Delete the remote ticket branch** — delegated `developer`: `git push origin --delete opencode/ticket-<n>-<slug>-<abbrev>` (developer is the only delegated actor for `git push origin --delete`; ticket session itself never runs this).

#### 3e. Out-of-band merges (GitHub UI)

If the user merges the sub-PR via GitHub UI instead of the gate: `dev-loop-watch.sh` detects the state change (PR state MERGED), the poller or user message wakes the develop orchestrator, which verifies via `gh pr view --json state`, then runs step 3d's cleanup.

### 4. State transitions inside the loop

The bounded ticket session owns `state:in-progress` (set during `ticket-lifecycle` §0 Bootstrap) and `state:ready-for-review` (set when the sub-PR opens, after `code_review_gate:` is posted). The develop orchestrator owns any subsequent state changes (`state:blocked` on `BLOCKED`, etc.). All transitions go through `issue-state-transition.sh <repo> <n> <state>` delegated to `developer`.

### 5. Failure handling

| Failure | Where it surfaces | Response |
|---|---|---|
| `worktree-manager` returns `blocker_code` | develop orchestrator loop | Surface verbatim, stop, do not retry. |
| `worktree-manager` returns `blocker_code: "KICKOFF_FAILED"` (advisory only) | develop orchestrator loop | Surface advisory in lifecycle log; brief file fallback stands. Retry via `worktree-manager` `kickoff` action, or the user opens the GUI session and types anything. **Do not pause the batch.** |
| `dev-loop-batch.sh` exits 1 | develop orchestrator loop | All tickets done → exit loop, go to step 6. |
| Ticket `BLOCKED: ENV_BLOCKED` after one repair | ticket session → develop orchestrator | Surface `recommended_env_fix`, pause batch. |
| Ticket `BLOCKED: STABILIZATION_EXHAUSTED` (CI fail after 3 iterations) | ticket session | Surface verbatim, pause batch. |
| Ticket `BLOCKED: CROSS_TICKET_REVIEW` | ticket session | Hand off to `architect-feature-signoff` immediately (skip step 6). |
| Sub-PR merge fails (branch protection / conflict) | develop orchestrator | Surface `gh pr view --json mergeable`, pause batch. |
| Remote-branch delete fails (protected / already gone) | develop orchestrator cleanup | Non-fatal: log, continue. Surface as advisory at feature close. |
| User merges sub-PR themselves | develop orchestrator | `gh pr view --json state` confirms MERGED; proceed to worktree + remote-branch cleanup. |
| User says "happy" but PR not yet merged | develop orchestrator | Orchestrator merges the sub-PR (delegated developer, with explicit `cd`/`git -C`), then cleanup. |
| In-session `session_notify` delivery fails (develop_session_id stale) | ticket session → develop orchestrator | The `ticket_report:` comment is the mandatory durable channel; the poller will wake the develop orchestrator within one poll interval. |
| Poller disabled / down | develop orchestrator | `dev-loop-watch.sh` is still agent-invocable; the user can manually trigger a wake. |

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
- Never dispatch ticket sessions via the `task` tool — the auto-started GUI session for the ticket worktree IS the ticket session. The `task` tool would inherit the `develop` cwd and `checkout-contract.sh --verify` would reject the subagent.
- Never run `git push origin --delete` from the develop orchestrator session itself — delegate to a `developer` Task with explicit `cd`/`git -C`. This is the only branch-deleting actor.
- Never load `orchestrate-verification` for ticket-mode work — ticket sessions self-dispatch `code-review` inside `ticket-lifecycle`.
- Never modify a remote ticket branch (`opencode/ticket-...`) except to delete it after its sub-PR merges.
- Children never create, switch, checkout, or rename branches (Hard Rule §82). The develop orchestrator is the only branch-switching actor.
- The develop orchestrator never edits code or commits itself.
- Wake messages that don't match an active loop in the lifecycle log are ignored (idempotent — "ignore if not yours").
- After kicking a batch, **end the turn**. Do not poll. Wakes arrive via `session_notify` (in-session), the poller (out-of-band), or user messages.

## See also

- `ticket-lifecycle` — the ticket session contract (§0 Bootstrap is the single source of truth for how the ticket self-starts).
- `architect-feature-signoff` — the post-merge feature audit + sign-off owner.
- `feature-worktree` — worktree-creation JSON shapes + naming conventions still apply.
- `agents/worktree-manager.md` — `create_ticket` now passes `kickoff_agent` + `kickoff_message`; `kickoff` action retries failed injections.
- `skills/github-issue-run/lib/dev-loop-watch.sh` — agent-invocable per-issue watcher (consumes `ticket_report:` comments).
- `scripts/dev-loop-poller.sh` — server-host cron poller that wakes the develop orchestrator via `DEV_LOOP_WAKE`.