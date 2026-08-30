---
name: orchestrate
description: Develop-branch outer-loop coordinator — bootstrap + work selection, feature worktree + push, batch kickoff of coder sessions per ticket, PR approval gate, merge + worktree/remote-branch cleanup, re-batch, feature-architect handoff, sandbox lane.
modelTier: "fast"
roleReminder: "Loaded by the `orchestrate` primary agent on the develop branch. The orchestrator never executes tickets — coder sessions do. Wake contract: in-session `session_notify` (primary), `DEV_LOOP_WAKE` from the poller, any user message → run `dev-loop-watch.sh` first."
---

> Hard Rules live in `agents/orchestrate.md`; this skill owns the **per-impl-repo develop-loop** body. The orchestrator owns outer-loop coordination only: bootstrap, work selection, feature worktree, batch kickoff, PR approval gate, merge + cleanup, re-batch, handoff. Ticket execution lives in `coder` sessions loading `ticket-lifecycle`.

## Scope

Run the **develop** branch as the single persistent orchestration session for one `(feature:<slug>, impl-repo)` pair. From `develop`, create the feature worktree, then **for each runnable ticket, create a ticket worktree + kick the auto-started GUI session** with a short pointer message (the coder session loads `ticket-lifecycle`, reads the brief file the plugin wrote into the worktree gitdir, and reconstructs the rest from GitHub). The develop loop only reacts to terminal ticket reports (`READY_FOR_HUMAN_REVIEW` | `BLOCKED`) — posted as `ticket_report:` comments on the issue and best-effort injected back via `session_notify`. When all tickets merge into the feature branch, hand off to `architect-feature-signoff`.

The develop loop does **not** dispatch ticket subagents via the `task` tool. Subagents inherit the parent's cwd (`develop`), so they would land on the wrong branch and `checkout-contract.sh --verify` would correctly reject them (`SubtaskPartInput` in the installed SDK has no `directory` field). The auto-started GUI session for the ticket worktree IS the coder session — it has the correct cwd by construction.

## Entry conditions

- `agents/orchestrate.md` permission block includes `orchestrate` in the `skill:` allow object — otherwise loading fails with `SKILL_UNAVAILABLE`.
- Bootstrap finished; the user picked a `feature:<slug>` from the menu.
- `opencode-run impl orchestrate-readiness-check <slug>` returned PASS (non-empty `stages[]` on every open ticket; every impl repo in `docs/agents/repos.md` has a `compose_test_file`).
- `checkout_contract` captured from `scripts/checkout-contract.sh` (`develop` branch is expected; protected branch confirmed).

## §1 Work-selection menu (branch-aware)

### Menu A — on a protected branch (`develop` / `main` / `master`, `is_linked_worktree: false`)

The user is starting fresh with no feature worktree yet. Sandbox is not offered here (there is no feature branch to build yet).

```text
What do you want to do?

(1) Start a new feature — give me the `feature:<slug>` and I'll create the feature worktree, then run every ticket end-to-end to a ready-for-review PR. (recommended)
(2) Resume a feature — reattach to a feature or ticket worktree from a previous session and continue its queue.
(3) Remediation loop — re-check PR feedback / CI after you pushed fixes (routes to architect option 4 → R).
(4) Something else (debug, refactor, doc review) — describe the task; I'll usually route you to `architect`.
```

For `(1)`, capture the kebab-case slug, run `opencode-run impl orchestrate-readiness-check <slug>` (PASS requires non-empty `stages[]` and a `compose_test_file` for every impl repo in the registry; FAIL stops and returns to spec architect option 1), then load the develop-loop section below. The develop loop creates the feature worktree via `worktree-manager`, pushes `opencode/feat-<slug>`, and for each runnable ticket creates a ticket worktree with a `kickoff_message` (the plugin writes `<gitdir>/opencode-ticket-brief.json` and injects the message into the auto-started GUI session via `session.promptAsync` — that auto-started session IS the coder session and loads `ticket-lifecycle`).

For `(2)`, Task `worktree-manager` `list` to discover existing worktrees; if one matches a `feature:<slug>`, capture that slug and continue. If no worktrees exist, tell the user and fall back to `(1)`.

### Menu B — inside a feature or ticket worktree (`is_linked_worktree: true`)

```text
What do you want to do?

(1) Build / refresh this worktree in Sysbox sandbox — compose build/test + optional review URL.
(2) Remediation loop — re-check PR feedback / CI after you pushed fixes (routes to architect option 4 → R).
(3) Something else (debug, refactor, doc review) — describe the task; I'll usually route you to `architect`.
```

**Note:** Menu B's old "run the next ticket in this worktree" option is gone. You're inside a worktree that already belongs to a coder session — switch this session's agent to `coder` and say `begin` to run the ticket. The orchestrator here owns sandbox + remediation routing only.

For `(1)` (Menu B only), load `orchestrate-sandbox`; do not enter the GitHub queue. For `(2)` (either menu), stop with the implementation architect Phase R handoff. For `(3)` (either menu), route to architect unless the message supplies an explicit queue or sandbox request.

## §2 Environment state

Track `worktree_env_checked`, canonical `{wt_root, main_root, files[]}` evidence, `preflight_repair_attempted`, `sandbox_status`, `preflight_skipped_on_protected_branch`, and `auto_spawn_consent` (set on first prompt). Do not create an artifact for these values. One automatic repair pass is allowed; after a second identical report, stop with one `recommended_env_fix` and `LOOP_DETECTED` where applicable.

## §3 Readiness + one-shot consent

1. Confirm readiness gate passed; record `readiness_status: PASS` in the lifecycle log.
2. Ask the user exactly once, record the answer as `auto_spawn_consent`:

   ```text
   Auto-spawn all runnable tickets for <slug> and only stop for human PR review? (yes/no)
   ```

   - **yes** → set `auto_spawn: true`. The loop dispatches every DAG-respecting ticket without further prompts; the only human gate is per-PR approval.
   - **no** → fall back to per-batch auto-vs-manual scheduling for this run.

## §4 Feature worktree + push

Dispatch `worktree-manager` `create_feature`:

```json
{ "action": "create_feature", "slug": "<slug>", "base": "develop" }
```

On success, record `{ name: "feat-<slug>", branch: "opencode/feat-<slug>", directory }` in the lifecycle log. Push the feature branch from the develop orchestrator's own checkout via a delegated `developer` Task (`load: minimal`, `git push -u origin opencode/feat-<slug>`). The plugin does not push.

If `worktree-manager` returns any `blocker_code`, surface it verbatim and stop.

## §5 Batch loop (silent except the single PR-review gate)

```text
while true:
  batch_json=$(bash <OC>/scripts/dev-loop-batch.sh <slug>)
  if batch is empty: break

  for entry in batch:
    ticket = entry.number
    title  = entry.title
    abbrev = <derive from title or pass via entry if worktree-manager echoes it>
    branch_name = "opencode/ticket-<n>-<slug>-<abbrev>"

    # 5a. create ticket worktree + kick the auto-started GUI session
    kickoff_message = compose_kickoff_message(
        issue=entry, feature_slug=slug, branch=branch_name,
        worktree_dir=DIRECTORY_FROM_RESPONSE, brief_file=<gitdir>/opencode-ticket-brief.json)

    dispatch worktree-manager create_ticket {
      issue, slug, base: opencode/feat-<slug>, title,
      auto_spawn: true,
      kickoff_agent: "coder",
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
      # The poller scripts/dev-loop-poller.sh + dev-loop-watch.sh will detect
      # the ticket_report: comment regardless of how the ticket was kicked.

  # 5b. wait for terminal reports (one per ticket in batch)
  #     wakes come from: (i) session_notify terminal-report injection (primary),
  #                       (ii) poller scripts/dev-loop-poller.sh firing DEV_LOOP_WAKE,
  #                       (iii) any user message — run dev-loop-watch.sh first.
  # End the turn after batch kickoff; do not block.
```

### §5a. Compose the kickoff message

The message is a short pointer — truncation-proof by design. The coder session reconstructs the full payload from the brief file + GitHub.

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

### §5b. Wake contract

- After kicking the batch, **end the turn**. Wakes (in priority order):
  1. **In-session `session_notify`** — when a coder session posts its terminal report, the develop orchestrator receives an injected message and runs the PR-approval gate for that ticket.
  2. **Poller `DEV_LOOP_WAKE`** — `scripts/dev-loop-poller.sh` (server-host cron) detects `ticket_report:` comment deltas and wakes the develop orchestrator.
  3. **Any user message** — run `scripts/dev-loop-watch.sh` first, process deltas, then handle the message.
- Wake contract: incoming message begins with `DEV_LOOP_WAKE: { repo, feature, reason }` → run `scripts/dev-loop-watch.sh`; if no active loop for that feature is in the lifecycle log, ignore (idempotent — "ignore if not yours").

### §5c. PR-approval gate

For each `READY_FOR_HUMAN_REVIEW` (received via `session_notify` or by parsing the latest `ticket_report:` comment from `scripts/dev-loop-watch.sh`):

```text
notify user: "PR ready for review: <pr_url>"   # ONLY HUMAN GATE
wait for user: "yes, happy with that ticket" (or user has already merged)
```

### §5d. Merge + cleanup

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

4. **Delete the remote ticket branch** — delegated `developer`: `git push origin --delete opencode/ticket-<n>-<slug>-<abbrev>` (developer is the only delegated actor for `git push origin --delete`; coder session itself never runs this).

### §5e. Out-of-band merges (GitHub UI)

If the user merges the sub-PR via GitHub UI instead of the gate: `scripts/dev-loop-watch.sh` detects the state change (PR state MERGED), the poller or user message wakes the develop orchestrator, which verifies via `gh pr view --json state`, then runs step §5d's cleanup.

## §6 State transitions inside the loop

The coder session owns `state:in-progress` (set during `ticket-lifecycle` §0 Bootstrap) and `state:ready-for-review` (set when the sub-PR opens, after `code_review_gate:` is posted). The develop orchestrator owns any subsequent state changes (`state:blocked` on `BLOCKED`, etc.). All transitions go through `scripts/issue-state-transition.sh <repo> <n> <state>` delegated to `developer`.

## §7 Failure handling

| Failure | Where it surfaces | Response |
|---|---|---|
| `worktree-manager` returns `blocker_code` | develop orchestrator loop | Surface verbatim, stop, do not retry. |
| `worktree-manager` returns `blocker_code: "KICKOFF_FAILED"` (advisory only) | develop orchestrator loop | Surface advisory in lifecycle log; brief file fallback stands. Retry via `worktree-manager` `kickoff` action, or the user opens the GUI session and types anything. **Do not pause the batch.** |
| `scripts/dev-loop-batch.sh` exits 1 | develop orchestrator loop | All tickets done → exit loop, go to §8. |
| Ticket `BLOCKED: ENV_BLOCKED` after one repair | coder session → develop orchestrator | Surface `recommended_env_fix`, pause batch. |
| Ticket `BLOCKED: STABILIZATION_EXHAUSTED` (CI fail after 3 iterations) | coder session | Surface verbatim, pause batch. |
| Ticket `BLOCKED: CROSS_TICKET_REVIEW` | coder session | Hand off to `architect-feature-signoff` immediately (skip §8). |
| Ticket `BLOCKED: FALLBACK_EXHAUSTED` | coder session | Surface verbatim, pause batch. |
| Sub-PR merge fails (branch protection / conflict) | develop orchestrator | Surface `gh pr view --json mergeable`, pause batch. |
| Remote-branch delete fails (protected / already gone) | develop orchestrator cleanup | Non-fatal: log, continue. Surface as advisory at feature close. |
| User merges sub-PR themselves | develop orchestrator | `gh pr view --json state` confirms MERGED; proceed to worktree + remote-branch cleanup. |
| User says "happy" but PR not yet merged | develop orchestrator | Orchestrator merges the sub-PR (delegated developer, with explicit `cd`/`git -C`), then cleanup. |
| In-session `session_notify` delivery fails (develop_session_id stale) | coder session → develop orchestrator | The `ticket_report:` comment is the mandatory durable channel; the poller will wake the develop orchestrator within one poll interval. |
| Poller disabled / down | develop orchestrator | `scripts/dev-loop-watch.sh` is still agent-invocable; the user can manually trigger a wake. |

## §8 Hand off to feature-architect

When `scripts/dev-loop-batch.sh` exits 1 and there are no `BLOCKED` tickets, **all** tickets have been merged into `opencode/feat-<slug>`. The develop orchestrator emits exactly:

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

and pauses. The user (or the spec session) starts the **feature-architect session** inside the feature worktree, where `architect-feature-signoff` takes over: full audit, feature-mode code-review, one-shot CodeRabbit (medium/hard), `pr_stabilization`, `scripts/feature-finish-pr.sh`, accept (`state:done`), merge with user confirmation, Phase R remediation if acceptance is unmet.

## §9 Close-loop resume

After the feature-architect merges the feature PR, the develop orchestrator resumes:

1. Delegated `developer`: `git push origin --delete opencode/feat-<slug>`.
2. Dispatch `worktree-manager` `delete { directory: <feature worktree dir> }`.
3. Delegated `developer` (in main checkout): `git fetch && git pull --ff-only origin develop`.
4. Emit one of:
   - `feature:<slug> complete; ready for spec close` (no more features queued), or
   - `feature:<slug> complete; ready for next feature` (loop continues).

## §10 Worktree conventions

Naming convention is `feat-<slug>` for a feature, `ticket-<issue>-<slug>-<abbrev>` for a ticket. The server auto-prefixes `opencode/`. `<abbrev>` is a 3–6-word kebab-case slug derived from the issue title by `worktree-manager` at `create_ticket` time; collisions within the same feature are suffixed `-2`, `-3`, … Branches always look like `opencode/feat-<slug>` and `opencode/ticket-<issue>-<slug>-<abbrev>` (never `feature/...` or `ticket/...` on the wire).

All worktree lifecycle (create, list, delete, reset, kickoff) is delegated to the `worktree-manager` subagent, which calls the `worktree_*` tools registered by `plugins/worktree.js`. **Raw git worktree subcommands (`worktree add`, `worktree remove`, `branch opencode/...`) are forbidden** — they bypass GUI registration and are not coordinated with session start.

Restart / recovery for stuck worktrees (post `opencode-server` restart, stale state): dispatch `worktree-manager` `reset { directory }`. If worktrees are stuck in the GUI / `worktree_list` after a failed delete (WorktreeNotGitError), dispatch `worktree-manager` `recover { directory }` — the system's sanctioned `rewrite-worktree-gitdirs.py` + session deregister. Never raw `git worktree`.

## §11 Hand-off markers

| Marker | Emitted by | Consumed by |
|---|---|---|
| `HANDOFF_TO_FEATURE_ARCHITECT` | develop orchestrator when the last ticket merges into `opencode/feat-<slug>` | architect agent in `opencode/feat-<slug>` (`architect-feature-signoff`) |
| `READY_FOR_HUMAN_REVIEW` | coder session when sub-PR is green and comment-clean | develop orchestrator surfaces to user (single human gate per PR) |
| `BLOCKED` | coder session on preflight-after-repair, CI-exhaustion, fallback-exhaustion, or cross-ticket review | develop orchestrator surfaces verbatim and pauses the batch |
| `ticket_report:` (issue comment) | coder session on terminal report | develop orchestrator's `scripts/dev-loop-watch.sh` + `scripts/dev-loop-poller.sh` — durable wake channel and out-of-band merge detector |
| `DEV_LOOP_WAKE: { repo, feature, reason }` | poller (`scripts/dev-loop-poller.sh`) when `ticket_report:` delta detected | develop orchestrator; ignored if no active loop for that feature |

There is no ticket-dispatch marker — the coder session is the auto-started GUI session for the worktree, not a `task`-tool dispatch. The `session_notify` tool injects report-back messages into an existing session via `POST /session/{id}/prompt_async`; it does not dispatch a new subagent.

## Hard rules for the develop orchestrator

- Never call `worktree_*` tools directly — delegate to `worktree-manager`.
- Never dispatch ticket sessions via the `task` tool — the auto-started GUI session for the ticket worktree IS the coder session. The `task` tool would inherit the `develop` cwd and `scripts/checkout-contract.sh --verify` would reject the subagent.
- Never run `git push origin --delete` from the develop orchestrator session itself — delegate to a `developer` Task with explicit `cd`/`git -C`. This is the only branch-deleting actor.
- Children never create, switch, checkout, or rename branches. The develop orchestrator is the only branch-switching actor.
- The develop orchestrator never edits code or commits itself.
- Wake messages that don't match an active loop in the lifecycle log are ignored (idempotent — "ignore if not yours").
- After kicking a batch, **end the turn**. Do not poll. Wakes arrive via `session_notify` (in-session), the poller (out-of-band), or user messages.
- On `worktree-manager` failure, surface the `blocker_code` verbatim and stop. Never retry, never fall back, never skip.

## See also

- `agents/orchestrate.md` — outer-loop host posture.
- `agents/coder.md` + `skills/ticket-lifecycle/SKILL.md` — the ticket session.
- `architect-feature-signoff` — the post-merge feature audit + sign-off owner.
- `agents/worktree-manager.md` — `create_ticket` passes `kickoff_agent: "coder"` + `kickoff_message`; `kickoff` action retries failed injections.
- `scripts/dev-loop-batch.sh` — DAG-respecting batch discovery.
- `scripts/dev-loop-watch.sh` — agent-invocable per-issue watcher (consumes `ticket_report:` comments).
- `scripts/issue-state-transition.sh`, `scripts/checkout-contract.sh`, `scripts/pr-stabilize-watch.sh`, `scripts/feature-finish-pr.sh` — moved lib scripts.
- `scripts/dev-loop-poller.sh` — server-host cron poller that wakes the develop orchestrator via `DEV_LOOP_WAKE`.
- `plugins/worktree.js` — `worktree_create` (kickoff params) and `session_notify`.
- `skills/orchestrate-sandbox/SKILL.md` — sandbox lane (Menu B option 1).