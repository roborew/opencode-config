---
name: orchestrate
description: Develop-branch outer-loop coordinator — bootstrap + work selection, feature worktree + push, batch kickoff of coder sessions per ticket, PR approval gate, merge + worktree/remote-branch cleanup, re-batch, feature coder kickoff + feature merge on approval.
modelTier: "fast"
roleReminder: "Loaded by the `orchestrate` primary agent on the develop branch. The orchestrator never executes tickets — coder sessions do. Wake contract: in-session `session-manager.notify` (primary), `DEV_LOOP_WAKE` from the poller, any user message → run `dev-loop-watch.sh` first."
---

> Hard Rules live in `agents/orchestrate.md`; this skill owns the **per-impl-repo develop-loop** body. The orchestrator owns outer-loop coordination only: bootstrap, work selection, feature worktree, batch kickoff, PR approval gate, merge + cleanup, re-batch, feature coder kickoff, feature merge on approval. Ticket execution lives in `coder` sessions loading `ticket-lifecycle`; feature-mode sign-off lives in `coder` sessions loading `feature-review`. The orchestrator never verifies code-review or CodeRabbit evidence — terminal reports plus human approval are its only gates.
>
> **You have no bash tool.** Every shell invocation in this skill — `scripts/checkout-contract.sh`, `opencode-run impl orchestrate-readiness-check`, `scripts/dev-loop-batch.sh`, `scripts/dev-loop-watch.sh`, `gh pr view` — is dispatched as a `developer` Task with `load: minimal` and the exact command to run. You also have no `worktree_*` or `session_*` tools: worktree lifecycle goes through `worktree-manager`; session messaging goes through `session-manager`. Never conclude "I can't run X because I have no bash" — delegate it to a `developer` Task.</oldString>

## Scope

Run the **develop** branch as the single persistent orchestration session for one `(feature:<slug>, impl-repo)` pair. From `develop`, create the feature worktree, then **for each runnable ticket, create a ticket worktree + kick the auto-started GUI session** with a short pointer message (the coder session loads `ticket-lifecycle` and reconstructs the rest from the branch + GitHub — no brief file is written). The develop loop only reacts to terminal ticket reports (`READY_FOR_HUMAN_REVIEW` | `BLOCKED`) — posted as `ticket_report:` comments on the issue and best-effort injected back via `session-manager.notify`. When all tickets merge into the feature branch, kick the **feature coder** (same `coder` agent, loading `feature-review`) for the final verification + feature PR + `feature_report:`.

The develop loop does **not** dispatch ticket subagents via the `task` tool. Subagents inherit the parent's cwd (`develop`), so they would land on the wrong branch and `checkout-contract.sh --verify` would correctly reject them (`SubtaskPartInput` in the installed SDK has no `directory` field). The auto-started GUI session for the ticket worktree IS the coder session — it has the correct cwd by construction.

## Entry conditions

- `agents/orchestrate.md` permission block includes `orchestrate` in the `skill:` allow object — otherwise loading fails with `SKILL_UNAVAILABLE`.
- §0 Bootstrap completed: `checkout_contract` captured via a delegated `developer` Task running `scripts/checkout-contract.sh`; readiness check passed — run via a delegated `developer` Task; the user picked a `feature:<slug>` from the menu.

## §0 Bootstrap (fresh session — before the menu)

Runs automatically on every fresh session, before the work-selection menu. Never skip it, and never present the menu with the gate unverified.

1. **Checkout identity gate (mandatory).** Dispatch one `developer` Task with `load: minimal`:

   ```text
   Task developer load: minimal
   bash "${OPENCODE_CONFIG:-$HOME/.config/opencode}/scripts/checkout-contract.sh"
   ```

   Require `status: ok`, repo root, branch, worktree status, main checkout root, protected-branch status, head SHA, and branch policy. Capture `is_linked_worktree` and `branch_policy` — §1 uses them to pick the menu. Expected: branch `develop` in the main checkout (→ Menu A) or a linked worktree branch (→ §1 worktree routing). On mismatch, surface `CHECKOUT_CONTRACT_FAILED` verbatim and stop — do not present the menu and do not offer improvised alternatives.

2. **Claude Context readiness.** If the `claude-context` MCP tools are available, check indexing status for the workspace path; if unavailable or indexing fails, record `MCP_FALLBACK` (discovery-heavy children enforce their own readiness gate).

3. Present the work-selection menu (§1) — task-oriented options only. Never surface lifecycle states, skill names, or routing rows as user-facing options.

## §1 Work-selection menu (branch-aware)

### Menu A — on a protected branch (`develop` / `main` / `master`, `is_linked_worktree: false`)

The user is starting fresh with no feature worktree yet.

```text
What do you want to do?

(1) Start a new feature — give me the `feature:<slug>` and I'll create the feature worktree, then run every ticket end-to-end to a ready-for-review PR. (recommended)
(2) Resume a feature — reattach to a feature or ticket worktree from a previous session and continue its queue.
(3) Remediation loop — re-check PR feedback / CI after you pushed fixes.
(4) Something else (debug, refactor, doc review) — describe the task; I'll usually route you to `architect`.
```

For `(1)`, capture the kebab-case slug, dispatch a `developer` Task (`load: minimal`) to run `opencode-run impl orchestrate-readiness-check <slug>` (PASS requires non-empty `stages[]` and a `compose_test_file` for every impl repo in the registry; FAIL stops and returns to spec architect option 1), then continue with §3. The develop loop creates the feature worktree via `worktree-manager`, pushes `opencode/feat-<slug>`, and for each runnable ticket creates a ticket worktree via `worktree-manager` (with `feature_branch` = the captured branch from §4) and dispatches `session-manager.kickoff` to inject the kickoff message into the auto-started GUI session — that auto-started session IS the coder session and loads `ticket-lifecycle`.

For `(2)`, Task `worktree-manager` `list` to discover existing worktrees; if one matches a `feature:<slug>`, capture that slug and continue. If no worktrees exist, tell the user and fall back to `(1)`.

### Worktree routing (when `is_linked_worktree: true`)

When the orchestrator's checkout is itself inside a worktree, present routing as a notice (not a menu):

```text
You are inside a worktree. Routing:
- ticket worktree (opencode/ticket-<n>-<slug>-<abbrev>): switch this session's agent to `coder` and say `begin` — the coder session loads `ticket-lifecycle` and owns the ticket inner loop.
- feature worktree (opencode/feat-<slug>): the feature coder session owns this — load `feature-review` and run the final verification + feature PR loop. The orchestrator kicks you here from `develop` after every ticket merges.
- design questions / planning / spec edits: route to `architect`.
- remediation / PR-feedback re-check: say `remediation` and the orchestrator re-batches the feature coder's `remediation:` issues and re-kicks the feature coder once they merge.
```

For Menu A `(3)` (remediation), stop with the same remediation wording — the develop orchestrator re-batches the feature coder's `remediation:` issues through the ticket pipeline, re-kicks the feature coder once they merge, and surfaces the new `feature_report:` to the user. For Menu A `(4)`, route to architect unless the message supplies an explicit queue request.

## §2 Environment state

Track `auto_spawn_consent` (set on first prompt) and `MCP_FALLBACK`. Do not create an artifact for these values. Environment verification itself is coder-owned (`ticket-lifecycle` §0 and `feature-review` §0).

## §3 Readiness + one-shot consent

1. Confirm readiness gate passed; record `readiness_status: PASS` in the lifecycle log.
2. Ask the user exactly once, record the answer as `auto_spawn_consent`:

   ```text
   Auto-spawn all runnable tickets for <slug> and only stop for human PR review? (yes/no)
   ```

   - **yes** → set `auto_spawn: true`. The loop dispatches every DAG-respecting ticket without further prompts; the only human gate is per-PR approval.
   - **no** → fall back to per-batch auto-vs-manual scheduling for this run.

## §4 Feature worktree + push

> One-op-per-Task applies here. `create_feature` is one dispatch. If the user request also names ticket worktrees, do **not** run `create_feature` and `create_ticket` in the same Task — dispatch `create_feature` first, then continue in the next Task once its envelope returns (per the Hard rule above). The §5 batch loop below already dispatches one `create_ticket` per loop iteration.

Dispatch `worktree-manager` `create_feature`:

```json
{ "action": "create_feature", "slug": "<slug>", "base": "develop" }
```

On success, record `{ name: "feat-<slug>", branch: <wr_feat.body.branch>, directory }` in the lifecycle log. The `branch` field (e.g. `opencode/feat-<slug>`) is captured here and passed as `feature_branch` to every `create_ticket` call in §5 — it is the safety link that prevents tickets from forking off `develop`/`main`. Push the feature branch from the develop orchestrator's own checkout via a delegated `developer` Task (`load: minimal`, `git push -u origin opencode/feat-<slug>`). The plugin does not push.

If `worktree-manager` returns any `blocker_code`, surface it verbatim and stop. If the response has no `branch` field, abort the §5 batch loop with `BLOCKED: FEATURE_WORKTREE_FAILED` before dispatching any ticket.

## §5 Batch loop (silent except the single PR-review gate)

```text
OC = "${OPENCODE_CONFIG:-$HOME/.config/opencode}"  # resolve once; pass this absolute path in every delegated script call

while true:
  batch_json = delegated developer (load: minimal):
    bash "$OC/scripts/dev-loop-batch.sh" <slug>

  # Relay contract: the developer returns the script stdout VERBATIM — one compact line:
  #   [{number, title, url, repo}, ...]
  # Entries never carry bodies or opencode-task-yaml (relay-safe by design). Coder sessions
  # reconstruct ticket context from GitHub (§5a); worktree-manager derives <abbrev> from the
  # title itself. Passing entry.url into the §5a kickoff message provides the issue_url.
  # Dependencies: a ticket runs only when every `Blocked by:` dep is satisfied — dep issue
  # CLOSED, dep labeled `state:done`, or the dep's sub-PR merged into opencode/feat-<slug>
  # (close-at-merge keeps ticket issues OPEN mid-loop, so the merged sub-PR is the in-loop
  # signal). Waves advance automatically as sub-PRs merge; independents run in parallel.
  # Exit codes: 1 + empty stdout → nothing runnable; 2 → gh/API failure — surface stderr
  # verbatim and stop. NEVER treat exit 2 as "all tickets done".

  if batch is empty: break

  for entry in batch:
    ticket = entry.number
    title  = entry.title
    url    = entry.url
    abbrev = <derive from title or pass via entry if worktree-manager echoes it>
    branch_name = "opencode/ticket-<n>-<slug>-<abbrev>"

    # 5a-i. Create ticket worktree (forked off the feature branch captured at §4)
    dispatch worktree-manager create_ticket {
      issue: ticket,
      slug,
      feature_branch: <captured wr_feat.body.branch from lifecycle log>,
      title,
      auto_spawn: true,
    }
    if response.body.directory is missing:
      surface blocker_code verbatim, continue to next entry (advisory — do not pause the batch)
      record { directory: null, branch: branch_name, abbrev, kickoff: "no_directory" }

    # 5a-ii. Compose the kickoff message (orchestrator owns this — it's the brief)
    kickoff_message = compose_kickoff_message(
        issue=entry, feature_slug=slug, branch=branch_name,
        worktree_dir=directory, develop_session_id=<ctx.sessionID>)

    # 5a-iii. Kick the coder session via session-manager (one atomic action: scoped-list-then-reuse-or-create-then-inject)
    # Resolution policy (locked): scoped-list filter by directory+agent → reuse if matching, create otherwise.
    # No global-list fallback in kickoff (see Global Invariants #8 in agents/orchestrate.md).
    ks = dispatch session-manager kickoff {
      directory,
      agent: "coder",
      message: kickoff_message,
    }
    # Tripwire: kickoff must never resolve to the orchestrator's own session.
    if ks.session_id == <ctx.sessionID>:
      surface "BLOCKED: KICKOFF_RESOLVED_TO_SELF" verbatim
      pause the batch
    record {
      directory, branch: branch_name, abbrev,
      session_id: ks.session_id, session_source: ks.session_source, resolution: ks.resolution,
      kickoff: ks.admitted ? "admitted" : "failed"
    }
    # Envelope shape (informational; admitted: true is the only success gate):
    #   { ok, action: "kickoff", session_id, session_source: reused|created, resolution: reused|created,
    #     reused: <bool>, agent_match: <bool>, admitted: <bool>, status, target_directory, agent,
    #     error, manualRecovery }
    if not ks.admitted:
      # Advisory for the batch (do NOT pause other tickets) — but NEVER silent:
      # relay the envelope's manualRecovery to the user immediately:
      #   notify user: "Kickoff failed for #<n>: <ks.manualRecovery>"
      # (recovery: worktree-manager `kickoff` retry (which now routes through
      #  session-manager), or the user opens the GUI session at <worktree dir>
      #  and types any message — ticket-lifecycle §0 reconstructs from GitHub)
      # The poller scripts/dev-loop-poller.sh + dev-loop-watch.sh will detect
      # the ticket_report: comment regardless of how the ticket was kicked.

  # 5b. wait for terminal reports (one per ticket in batch)
  #     wakes come from: (i) session-manager.notify terminal-report injection (primary),
  #                       (ii) poller scripts/dev-loop-poller.sh firing DEV_LOOP_WAKE,
  #                       (iii) any user message — run dev-loop-watch.sh first.
  # End the turn after batch kickoff; do not block.
```

### §5a. Compose the kickoff message

The message is a short pointer — truncation-proof by design. The coder session reconstructs the full payload from the kickoff message itself + the branch + GitHub (no brief file is written).

```text
execution_mode: github_issue_full
issue: OWNER/REPO#<n> (<issue_url>)
feature: feature:<slug> (base branch opencode/feat-<slug>)
expected_branch: opencode/ticket-<n>-<slug>-<abbrev>
worktree: <abs path>
develop_session_id: <ctx.sessionID>     # the develop orchestrator's session id — coder uses this for the terminal session-manager.notify injection
Load skill ticket-lifecycle and begin. The GitHub issue body (opencode-task-yaml) is the source of truth for stages[], acceptance, and test commands. Do not ask for a pasted brief; reconstruct anything missing per ticket-lifecycle §0 Bootstrap.
```

Compose it once per ticket; pass it verbatim to `session-manager.kickoff` as `message`. The session-manager subagent does scoped-list-then-reuse-or-create-then-inject atomically (never falls back to the unfiltered global session list — that path caused the self-resolve bug). The `kickoff` returns `session_source: reused|created` and `resolution: reused|created` so the orchestrator can audit which path was taken; the orchestrator's only success gate remains `admitted: true`. No brief file is written; the kickoff message is the contract.

### §5b. Wake contract

- After kicking the batch, **end the turn**. Wakes (in priority order):
  1. **In-session `session-manager.notify`** — when a coder session posts its terminal report, the develop orchestrator receives an injected message and runs the PR-approval gate for that ticket.
  2. **Poller `DEV_LOOP_WAKE`** — `scripts/dev-loop-poller.sh` (server-host cron) detects `ticket_report:` comment deltas and wakes the develop orchestrator.
  3. **Any user message** — dispatch a `developer` Task (`load: minimal`) to run `scripts/dev-loop-watch.sh`, process deltas, then handle the message.
- Wake contract: incoming message begins with `DEV_LOOP_WAKE: { repo, feature, reason }` → dispatch a `developer` Task (`load: minimal`) to run `scripts/dev-loop-watch.sh`; if no active loop for that feature is in the lifecycle log, ignore (idempotent — "ignore if not yours").

### §5c. PR-approval gate

For each `READY_FOR_HUMAN_REVIEW` (received via `session-manager.notify` or by parsing the latest `ticket_report:` comment from `scripts/dev-loop-watch.sh`):

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

If the user merges the sub-PR via GitHub UI instead of the gate: `scripts/dev-loop-watch.sh` detects the state change (PR state MERGED), the poller or user message wakes the develop orchestrator, which verifies via a delegated `developer` Task (`gh pr view --json state`), then runs step §5d's cleanup.

## §6 State transitions inside the loop

The coder session owns `state:in-progress` (set during `ticket-lifecycle` §0 Bootstrap) and `state:ready-for-review` (set when the sub-PR opens, after `code_review_gate:` is posted). The develop orchestrator owns any subsequent state changes (`state:blocked` on `BLOCKED`, etc.). All transitions go through `scripts/issue-state-transition.sh <repo> <n> <state>` delegated to `developer`.

## §7 Failure handling

| Failure | Where it surfaces | Response |
|---|---|---|
| `worktree-manager` returns `blocker_code` | develop orchestrator loop | Surface verbatim, stop, do not retry. |
| `worktree-manager` returns `WORKTREE_TOOLS_NOT_REGISTERED` | develop orchestrator loop | The worktree plugin is not loaded in this environment. Surface `next_action` verbatim and stop: deploy `plugins/worktree.js` into the config `plugins/` dir, restart opencode-server, confirm the boot log shows `[worktree-plugin] loaded` before retrying. |
| `worktree-manager` returns `blocker_code: "KICKOFF_FAILED"` (advisory only) | develop orchestrator loop | Relay the envelope's `manualRecovery` to the user IMMEDIATELY (never silent); record advisory in lifecycle log; the kickoff message is the contract and the coder session can still bootstrap from the branch + GitHub. Retry via `worktree-manager` `kickoff` action (which now routes through `session-manager`), or the user opens the GUI session and types anything. **Do not pause the batch.** |
| `session-manager` returns `SESSION_TOOLS_NOT_REGISTERED` | develop orchestrator loop | The session-manager plugin is not loaded in this environment. Surface `next_action` verbatim and stop: deploy `plugins/session-manager.js` into the config `plugins/` dir, restart opencode-server, confirm the boot log shows `[session-manager-plugin] messaging tools loaded` before retrying. |
| `session-manager` returns `SESSION_API_FAILED` (advisory only) | develop orchestrator loop | Relay the envelope's `manualRecovery` to the user IMMEDIATELY (never silent); record advisory in lifecycle log; the kickoff message is the contract and the coder session can still bootstrap from the branch + GitHub. **Do not pause the batch.** The `kickoff` action no longer returns `NO_SESSION_IN_DIRECTORY` — an empty scoped list now means "create", not "fail". |
| `session-manager.kickoff` returns `session_id == <ctx.sessionID>` (`BLOCKED: KICKOFF_RESOLVED_TO_SELF`) | develop orchestrator loop (tripwire per Global Invariants #8) | Pause the batch and surface `BLOCKED: KICKOFF_RESOLVED_TO_SELF` verbatim. This indicates a regression — `session-manager.kickoff` resolved to the orchestrator's own session instead of creating/reusing one for the worktree directory. Investigate `agents/session-manager.md` (scoped list filter, agent match) before retrying. Should never fire post-fix. |
| `scripts/dev-loop-batch.sh` exits 1 | develop orchestrator loop | All tickets done → exit loop, go to §8. |
| `scripts/dev-loop-batch.sh` exits 2 | develop orchestrator loop | gh/API failure — surface stderr verbatim, stop. Never treat as "all tickets done" (an empty lifecycle log + exit 2 is a transport failure, not completion). |
| Ticket `BLOCKED: ENV_BLOCKED` after one repair | coder session → develop orchestrator | Surface `recommended_env_fix`, pause batch. |
| Ticket `BLOCKED: STABILIZATION_EXHAUSTED` (CI fail after 3 iterations) | coder session | Surface verbatim, pause batch. |
| Ticket `BLOCKED: CROSS_TICKET_REVIEW` | coder session | Surface verbatim, route to the feature coder's remediation flow (`feature-review` §8) — pause the batch until the feature coder creates `remediation:` issues and the orchestrator re-batches. |
| Ticket `BLOCKED: FALLBACK_EXHAUSTED` | coder session | Surface verbatim, pause batch. |
| Sub-PR merge fails (branch protection / conflict) | develop orchestrator | Surface `gh pr view --json mergeable`, pause batch. |
| Remote-branch delete fails (protected / already gone) | develop orchestrator cleanup | Non-fatal: log, continue. Surface as advisory at feature close. |
| User merges sub-PR themselves | develop orchestrator | `gh pr view --json state` (delegated `developer`) confirms MERGED; proceed to worktree + remote-branch cleanup. |
| User says "happy" but PR not yet merged | develop orchestrator | Orchestrator merges the sub-PR (delegated developer, with explicit `cd`/`git -C`), then cleanup. |
| In-session `session-manager.notify` delivery fails (`develop_session_id` stale) | coder session → develop orchestrator | The `ticket_report:` comment is the mandatory durable channel; the poller will wake the develop orchestrator within one poll interval. |
| Poller disabled / down | develop orchestrator | `scripts/dev-loop-watch.sh` is still agent-invocable; the user can manually trigger a wake. |

## §8 Feature coder kickoff + feature merge

After `scripts/dev-loop-batch.sh` exits 1 and there are no `BLOCKED` tickets, every ticket has merged into `opencode/feat-<slug>`. **Kick the feature coder** (same `coder` agent, loading `feature-review`) in the feature worktree via `session-manager.kickoff`:

```text
session-manager.kickoff {
  directory: <feature worktree directory>,
  agent: coder,
  message: <pointer: feature slug, feat branch, "Load skill feature-review and begin">
}
```

End the turn after kicking. Do not poll. The feature coder owns the entire verification loop end-to-end (test suite, code-review gates, difficulty gates, docs, `state:done`, feature PR, bounded stabilization) and posts one `feature_report:` comment on the PRD parent + best-effort `session-manager.notify` back here.

### §8a. On `feature_report:` wake

When the feature coder wakes you (via `session-manager.notify` or poller or user message), read the terminal `feature_report:` status. You do **not** re-verify code-review or CodeRabbit evidence — every verification gate already ran inside the coder sessions; the terminal report plus the human approval below are your only gates.

- `READY_FOR_HUMAN_REVIEW` → capture `pr_url`, go to §8b.
- `BLOCKED: FEATURE_REMEDIATION` with `remediation:` issue numbers → re-batch those issues through the normal ticket pipeline (§5 batch loop); when they merge, kick the feature coder again.
- Any other `BLOCKED` → surface verbatim and pause the loop.

### §8b. Human gate

On READY, print exactly:

```text
Feature <slug> ready for final review: <pr_url>

I will merge the feature PR after "all reviewed" — say "all reviewed" to merge (squash, --delete-branch=false).
```

Then wait for the user's "all reviewed" message. Do not auto-merge.

### §8c. Merge the feature PR

On "all reviewed", dispatch a `developer` Task (`load: minimal`) with explicit `cd <feature worktree dir>` (and `git -C`):

```bash
gh pr merge <pr_url> --squash --delete-branch=false
```

On failure: surface `gh pr view --json mergeable` verbatim, pause. On success: continue.

### §8d. Hand off

After the feature PR merges, proceed to §9 close-loop resume, then emit one of:

- `feature:<slug> complete in <OWNER/REPO>; ready for spec feature-complete`, or
- `feature:<slug> complete in <OWNER/REPO>; ready for next feature` (loop continues).

## §9 Close-loop resume

When the feature PR merges, the develop orchestrator resumes:

1. Delegated `developer`: `git push origin --delete opencode/feat-<slug>`.
2. Dispatch `worktree-manager` `delete { directory: <feature worktree dir> }`.
3. Delegated `developer` (in main checkout): `git fetch && git pull --ff-only origin develop`.
4. Emit one of:
   - `feature:<slug> complete in <OWNER/REPO>; ready for spec feature-complete` (no more features queued), or
   - `feature:<slug> complete in <OWNER/REPO>; ready for next feature` (loop continues).

## §10 Worktree conventions

Naming convention is `feat-<slug>` for a feature, `ticket-<issue>-<slug>-<abbrev>` for a ticket. The server auto-prefixes `opencode/`. `<abbrev>` is a 3–6-word kebab-case slug derived from the issue title by `worktree-manager` at `create_ticket` time; collisions within the same feature are suffixed `-2`, `-3`, … Branches always look like `opencode/feat-<slug>` and `opencode/ticket-<issue>-<slug>-<abbrev>` (never `feature/...` or `ticket/...` on the wire).

All worktree lifecycle (create, list, delete, reset, kickoff retry) is delegated to the `worktree-manager` subagent, which calls the `worktree_*` tools registered by `plugins/worktree.js`. **Raw git worktree subcommands (`worktree add`, `worktree remove`, `branch opencode/...`) are forbidden** — they bypass GUI registration and are not coordinated with session start. Session messaging (kickoff, terminal-report notify) is delegated to the `session-manager` subagent, which calls the `session_*` tools registered by `plugins/session-manager.js`.

Restart / recovery for stuck worktrees (post `opencode-server` restart, stale state): dispatch `worktree-manager` `reset { directory }`. If worktrees are stuck in the GUI / `worktree_list` after a failed delete (WorktreeNotGitError), dispatch `worktree-manager` `recover { directory }` — the system's sanctioned `rewrite-worktree-gitdirs.py` + session deregister. Never raw `git worktree`.

## §11 Hand-off markers

| Marker | Emitted by | Consumed by |
|---|---|---|
| `feature_report:` (issue comment on PRD parent) | feature coder on terminal report | develop orchestrator reads the status: READY → §8b human gate → merge; `FEATURE_REMEDIATION` → re-batch `remediation:` issues; other BLOCKED → surface + pause |
| `READY_FOR_HUMAN_REVIEW` | coder session when sub-PR is green and comment-clean (ticket mode) | develop orchestrator surfaces to user (single human gate per PR) |
| `BLOCKED` | coder session on environment-after-repair, CI-exhaustion, fallback-exhaustion, or cross-ticket review | develop orchestrator surfaces verbatim and pauses the batch |
| `ticket_report:` (issue comment) | coder session on terminal report (ticket mode) | develop orchestrator's `scripts/dev-loop-watch.sh` + `scripts/dev-loop-poller.sh` — durable wake channel and out-of-band merge detector |
| `DEV_LOOP_WAKE: { repo, feature, reason }` | poller (`scripts/dev-loop-poller.sh`) when `ticket_report:` delta detected | develop orchestrator; ignored if no active loop for that feature |

There is no ticket-dispatch marker — the coder session is the auto-started GUI session for the worktree, not a `task`-tool dispatch. The `session-manager.notify` tool injects report-back messages into an existing session via `POST /session/{id}/prompt_async`; it does not dispatch a new subagent.

## Hard rules for the develop orchestrator

- Never call `worktree_*` tools directly — delegate to `worktree-manager`.
- **One worktree op per `worktree-manager` Task.** Every `create_feature` / `create_ticket` / `delete` / `reset` / `kickoff` call is its own Task — one op, one Task, one round-trip. If the user names N worktree ops in a single message (e.g. "create a feature worktree and two ticket worktrees"), dispatch N separate `worktree-manager` Tasks **in order**, each as its own `developer`-style dispatch with idempotent pre-checks (does the worktree already exist? if yes, exit fast). Never chain multiple `worktree_*` calls inside a single Task. Rationale: a hang or slow call in one chained op silently truncates the rest with no error payload; sequential one-per-Task dispatches stay sub-second on a warm daemon (measured: 3 creates ≈ 3.1s) and each emits a clean envelope on failure. If you spot a chained-worktree pattern in a user message or draft dispatch, flag it and split before acting.
- **One session-manager op per `session-manager` Task.** Every `kickoff` (per-ticket, feature-coder, retry) call is its own Task — one op, one Task, one round-trip. Never chain `create_ticket` + `session-manager.kickoff` for the same ticket into one Task: the create_ticket envelope is the input to the kickoff dispatch, and a failure in either must surface independently. The §5 loop already dispatches them in sequence as two Tasks.
- Never dispatch ticket sessions via the `task` tool — the auto-started GUI session for the ticket worktree IS the coder session. The `task` tool would inherit the `develop` cwd and `scripts/checkout-contract.sh --verify` would reject the subagent.
- Never run `git push origin --delete` from the develop orchestrator session itself — delegate to a `developer` Task with explicit `cd`/`git -C`. This is the only branch-deleting actor.
- Children never create, switch, checkout, or rename branches. The develop orchestrator is the only branch-switching actor.
- The develop orchestrator never edits code or commits itself.
- Wake messages that don't match an active loop in the lifecycle log are ignored (idempotent — "ignore if not yours").
- After kicking a batch, **end the turn**. Do not poll. Wakes arrive via `session-manager.notify` (in-session), the poller (out-of-band), or user messages.
- On `worktree-manager` failure, surface the `blocker_code` verbatim and stop. Never retry, never fall back, never skip.

## See also

- `agents/orchestrate.md` — outer-loop host posture.
- `agents/coder.md` + `skills/ticket-lifecycle/SKILL.md` — the ticket session.
- `skills/feature-review/SKILL.md` — the feature coder's verification + sign-off loop (same `coder` agent, different skill).
- `agents/worktree-manager.md` — `create_ticket` accepts `feature_branch` (the captured §4 branch) as the safety link; `kickoff` action retries failed injections by routing through `session-manager`.
- `agents/session-manager.md` — the single owner of session messaging for both directions (orchestrator kickoff, coder terminal-report notify).
- `scripts/dev-loop-batch.sh` — DAG-respecting batch discovery (single gh call; relay-safe slim output; exit 1 = done, exit 2 = gh failure).
- `scripts/dev-loop-watch.sh` — agent-invocable per-issue watcher (consumes `ticket_report:` comments).
- `scripts/issue-state-transition.sh`, `scripts/checkout-contract.sh`, `scripts/pr-stabilize-watch.sh`, `scripts/feature-finish-pr.sh` — shared lib scripts.
- `scripts/dev-loop-poller.sh` — server-host cron poller that wakes the develop orchestrator via `DEV_LOOP_WAKE`.
- `plugins/worktree.js` — `worktree_create_feature` / `worktree_create_ticket` / `worktree_list` / `worktree_delete` / `worktree_reset`.
- `plugins/session-manager.js` — `session_create` / `session_list` / `session_notify` (the `session-manager` subagent orchestrates these; no agent holds the plugin tools directly for messaging except `session-manager` itself).