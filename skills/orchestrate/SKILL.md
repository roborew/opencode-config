---
name: orchestrate
description: Develop-branch outer-loop coordinator — bootstrap + work selection, feature worktree + push, batch kickoff of coder sessions per ticket, PR approval gate, merge + worktree/remote-branch cleanup, per-merge re-batch, feature coder kickoff + feature merge on approval.
modelTier: "fast"
roleReminder: "Loaded by the `orchestrate` primary agent on the develop branch. The orchestrator never executes tickets — coder sessions do. Wake contract: in-session `session_notify` (primary), `DEV_LOOP_WAKE` from the poller, any user message → run `dev-loop-watch.sh` first."
---

> Hard Rules live in `agents/orchestrate.md`; this skill owns the **per-impl-repo develop-loop** body. The orchestrator owns outer-loop coordination only: bootstrap, work selection, feature worktree, batch kickoff, PR approval gate, merge + cleanup, per-merge re-batch, feature coder kickoff, feature merge on approval. Ticket execution lives in `coder` sessions loading `ticket-lifecycle`; feature-mode sign-off lives in `coder` sessions loading `feature-review`. The orchestrator never verifies code-review or CodeRabbit evidence — terminal reports plus human approval are its only gates.
>
> **You have no bash tool.** Every shell invocation in this skill — `scripts/checkout-contract.sh`, `opencode-run impl orchestrate-readiness-check`, `scripts/dev-loop-batch.sh`, `scripts/dev-loop-watch.sh`, `gh pr view` — is dispatched as a `developer` Task with `load: minimal` and the exact command to run. You also have no `worktree_*` tools: worktree lifecycle goes through `worktree-manager`. **You DO hold `session_*` plugin tools directly** (`session_kickoff` for ticket/feature coder kickoff, `session_list` for state queries, `session_notify` for terminal-report reception via the kickoff message's `develop_session_id`) — the previous `session-manager` subagent layer was removed and the choreography lives in plugin code. Never conclude "I can't run X because I have no bash" — delegate it to a `developer` Task.

## Scope

Run the **develop** branch as the single persistent orchestration session for one `(feature:<slug>, impl-repo)` pair. From `develop`, create the feature worktree, then **for each runnable ticket, create a ticket worktree + kick the auto-started GUI session** with a short pointer message (the coder session loads `ticket-lifecycle` and reconstructs the rest from the branch + GitHub — no brief file is written). The develop loop only reacts to terminal ticket reports (`READY_FOR_HUMAN_REVIEW` | `BLOCKED`) — posted as `ticket_report:` comments on the issue and best-effort injected back via `session_notify`. When all tickets merge into the feature branch, kick the **feature coder** (same `coder` agent, loading `feature-review`) for the final verification + feature PR + `feature_report:`.

The develop loop does **not** dispatch ticket subagents via the `task` tool. Subagents inherit the parent's cwd (`develop`), so they would land on the wrong branch and `checkout-contract.sh --verify` would correctly reject them (`SubtaskPartInput` in the installed SDK has no `directory` field). The auto-started GUI session for the ticket worktree IS the coder session — it has the correct cwd by construction.

After each sub-PR merges into the feature branch, the orchestrator fast-forwards the local feature ref, deletes the ticket worktree + remote ticket branch, and **per-merge re-batches** the remaining DAG before creating any new ticket worktrees. The §5-0 freshness gate guarantees the next ticket forks off code that includes every previously merged sub-PR — without it, `worktree_create_ticket` (which forks off the **local** `refs/heads/opencode/feat-<slug>` per `plugins/worktree.js:166`) would silently produce a stale worktree, and `ticket-lifecycle` §0.0 handshake step 6 would fail with `BLOCKED: TICKET_NOT_FORKED_FROM_FEATURE`.

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

2. **Linked-worktree env copy (only when `is_linked_worktree: true`).** When the orchestrator is itself running inside a linked worktree, dispatch ONE `worktree-sandbox` Task with `load: minimal` to copy `.env` / `.env.local` from the main checkout into the worktree. The agent drives the plugin tool `env_copy` from `plugins/sandbox.js`; it never writes bash. Skip when `is_linked_worktree: false` (the orchestrator's main-checkout path is already the source of truth).

   ```text
   Task worktree-sandbox load: minimal
   mode: env_copy
   worktree_path: <orchestrator cwd — absolute>
   main_path: <main checkout root from checkout-contract.sh>
   ```

   On `status: blocked` with `blocker_code: ENV_BLOCKED` — surface `recommended_env_fix` verbatim and stop. On `status: ok` — record `worktree_env_evidence` in the lifecycle log; do not dispatch again until the orchestrator is back in a different worktree.

3. **Claude Context readiness.** If the `claude-context` MCP tools are available, check indexing status for the workspace path; if unavailable or indexing fails, record `MCP_FALLBACK` (discovery-heavy children enforce their own readiness gate).

4. Present the work-selection menu (§1) — task-oriented options only. Never surface lifecycle states, skill names, or routing rows as user-facing options.

## §1 Work-selection menu (branch-aware)

### Menu A — on a protected branch (`develop` / `main` / `master`, `is_linked_worktree: false`)

The user is starting fresh with no feature worktree yet.

```text
What do you want to do?

(1) Start a new feature — give me the `feature:<slug>` and I'll create the feature worktree, then run every ticket end-to-end to a ready-for-ticket-review PR. (recommended)
(2) Resume a feature — reattach to a feature or ticket worktree from a previous session and continue its queue.
(3) Remediation loop — re-check PR feedback / CI after you pushed fixes.
(4) Something else (debug, refactor, doc review) — describe the task; I'll usually route you to `architect`.
```

For `(1)`, capture the kebab-case slug, dispatch a `developer` Task (`load: minimal`) to run `opencode-run impl orchestrate-readiness-check <slug>` (PASS requires non-empty `stages[]` and a `compose_test_file` for every impl repo in the registry; FAIL stops and returns to spec architect option 1), then continue with §3. The develop loop creates the feature worktree via `worktree-manager`, pushes `opencode/feat-<slug>`, and for each runnable ticket creates a ticket worktree via `worktree-manager` (with `feature_branch` = the captured branch from §4) and calls `session_kickoff` directly to inject the kickoff message into the auto-started GUI session — that auto-started session IS the coder session and loads `ticket-lifecycle`.

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

On success, record `{ name: "feat-<slug>", branch: <wr_feat.body.branch>, directory }` in the lifecycle log. The `branch` field (e.g. `opencode/feat-<slug>`) is captured here and passed as `feature_branch` to every `create_ticket` call in §5 — it is the safety link that prevents tickets from forking off `develop`/`main`. **The feature branch is pushed by the first coder session to receive a kickoff** (the feature coder at §8, or the first ticket coder at §5a). worktree-manager does not push. The orchestrator does not push. The coder session owns the handshake push via `developer` (`gh` for branch metadata, shell `git push` from the worktree cwd — see `ticket-lifecycle` §0.0 / `feature-review` §0.0).

If `worktree-manager` returns any `blocker_code`, surface it verbatim and stop. If the response has no `branch` field, abort the §5 batch loop with `BLOCKED: FEATURE_WORKTREE_FAILED` before dispatching any ticket.

## §5 Batch loop (silent except the single PR-review gate)

> **Worktree-manager dispatches are pure JSON envelopes.** The subagent owns its own procedures (see `agents/worktree-manager.md` §Procedures). Session messaging is now plugin-owned — the orchestrator calls `session_kickoff` / `session_list` / `session_notify` directly via the `session_*` plugin tools registered by `plugins/session-manager.js`. Do not include procedural narration, verification commands, or invented `blocker_code` values in the Task prompt — pass the action and its inputs, require `report_to_parent`, and surface the envelope verbatim on failure.

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

    # 5-0. Feature-branch freshness gate (mandatory precondition before create_ticket).
    #      Reason: worktree_create_ticket forks the new worktree off the LOCAL ref
    #      refs/heads/opencode/feat-<slug> (plugins/worktree.js:166 sends
    #      `base: <feature_branch>` which the server resolves locally — it does not
    #      fork off refs/remotes/origin/opencode/feat-<slug>). If the local feature
    #      ref is stale (e.g. a §5d fast-forward was skipped, or the user merged
    #      via the GitHub UI and §5e bypassed the ff), the next ticket forks off
    #      pre-merge code and ticket-lifecycle §0.0 step 6 fails with
    #      BLOCKED: TICKET_NOT_FORKED_FROM_FEATURE (or worktree-manager 8.5
    #      branch_local_up_to_date === false). This gate is the only thing that
    #      catches the §5e out-of-band-merge case (§5e used to skip the ff and the
    #      §5d ff alone was insufficient).
    #      Delegated developer Task, load: minimal, run in the feature worktree:
    #
    #        cd <feature worktree directory>
    #        git fetch origin "opencode/feat-<slug>"
    #        local=$(git rev-parse "refs/heads/opencode/feat-<slug>")
    #        remote=$(git rev-parse "refs/remotes/origin/opencode/feat-<slug>")
    #        echo "local=$local remote=$remote"
    #
    #      - Equal → proceed to 5a-i.
    #      - Not equal → ONE automatic repair attempt, guarded by the develop-
    #        pollution guard (the self-ff exemption at scripts/assert-merge-cwd.sh:122
    #        permits ASSERT_MERGE_REF == origin/<ASSERT_MERGE_BRANCH> in
    #        feature-worktree context):
    #
    #        cd <feature worktree directory>
    #        ASSERT_MERGE_CWD="<feature worktree dir>" \
    #        ASSERT_MERGE_BRANCH="opencode/feat-<slug>" \
    #        ASSERT_MERGE_REF="origin/opencode/feat-<slug>" \
    #        ASSERT_REPO="<OWNER/REPO>" \
    #        ASSERT_BRANCH_CONTEXT="feature-worktree" \
    #          source "${OPENCODE_CONFIG:-$HOME/.config/opencode}/scripts/assert-merge-cwd.sh"
    #        git merge --ff-only "origin/opencode/feat-<slug>"
    #
    #      - Re-check; still unequal OR any BLOCKED: * from the guard → surface
    #        BLOCKED: FEATURE_BRANCH_STALE with both SHAs verbatim, pause the batch,
    #        do NOT call create_ticket.
    #      - Also gate the feature worktree existence: if the feature worktree is
    #        gone, surface BLOCKED: FEATURE_BRANCH_STALE with feature_worktree_gone:
    #        true and recreate the feature worktree via worktree-manager.create_feature
    #        before continuing. Do NOT silently recreate and proceed — surface the
    #        code so the operator sees the recovery.

    # 5a-i. Create ticket worktree (forked off the feature branch captured at §4)
    #       Pure JSON envelope — worktree-manager owns the procedure. Do NOT include
    #       verification commands or invented blocker_code in the prompt; surface the
    #       envelope verbatim on failure. `repo` is the OWNER/REPO from entry and is
    #       passed through so worktree-manager's in-step-8.5 readiness check and the
    #       KICKOFF_ALREADY_DELIVERED precondition in kickoff step 2a can run
    #       `gh issue view` / `gh repo view` without re-deriving the repo.
    dispatch worktree-manager create_ticket {
      issue: ticket,
      slug,
      feature_branch: <captured wr_feat.body.branch from lifecycle log>,
      title,
      repo: entry.repo,
      auto_spawn: true,
    }
    if not response.ok:
      surface blocker_code verbatim, continue to next entry (advisory — do not pause the batch)
      record { directory: null, branch: branch_name, abbrev, kickoff: "no_directory" }

    # Tripwire per Global Invariants #12: the readiness check (worktree-manager step 8.5)
    # must have returned reachable + writable + branch_local_up_to_date + parent_merged.
    # The blocker_code is WORKTREE_PREFLIGHT_FAILED; surface verbatim and pause the batch
    # — do NOT retry by re-running create_ticket (Hard Rule 4 would suffix -2 and create
    # a sibling worktree).

    # 5a-ii. Compose the kickoff message (orchestrator owns this — it's the brief)
    kickoff_message = compose_kickoff_message(
        issue=entry, feature_slug=slug, branch=branch_name,
        worktree_dir=directory, develop_session_id=<ctx.sessionID>)

    # Cap gate per Global Invariants #11: read the lifecycle-log entry for this ticket;
    # if session_create_attempts >= session_create_cap (default 3), surface
    # BLOCKED: WORKTREE_SESSION_ATTEMPTS_EXCEEDED verbatim and pause the batch.

    # 5a-iii. KICKOFF_ALREADY_DELIVERED precheck (delegated developer Task — gh issue view
    #         against durable ticket_report: comments). Runs BEFORE session_kickoff to prevent
    #         re-kicking into a worktree whose coder has already finished. The previous
    #         worktree-manager.kickoff step 2a precheck moved here (the worktree-manager.kickoff
    #         action itself was deleted; the check lives in the orchestrator now).
    if "issue" in entry:
      precheck = dispatch developer load: minimal {
        bash -c '
          REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
          gh issue view '"<ticket>"' --repo "$REPO" --comments --json comments \
            -q ".comments[] | select(.body | test(\"^ticket_report:\")) | .id" \
            | head -n1
        '
      }
      if precheck.stdout.strip():
        surface "BLOCKED: KICKOFF_ALREADY_DELIVERED" verbatim
        pause the batch

    # 5a-iv. Kick the coder session via direct session_kickoff call (one atomic action:
    #         scoped-list-then-reuse-or-create-then-inject with ?directory=). No subagent,
    #         no model — the plugin owns the choreography. Resolution policy (locked):
    #         scoped list → reuse if matching, create otherwise. No global-list fallback
    #         in kickoff (see Global Invariants #8 in agents/orchestrate.md).
    #         Default `create_if_absent: true` preserves current behavior; pass
    #         `create_if_absent: false` to opt out of the auto-create (returns
    #         `NO_SESSION_FOR_WORKTREE`).
    ks = session_kickoff {
      directory,
      agent: "coder",
      message: kickoff_message,
      create_if_absent: true,
    }
    # Increment the lifecycle-log session_create_attempts counter for this ticket on
    # EVERY session_kickoff that performed a create branch, regardless of subsequent
    # session_notify outcome — the orphan is created at session_create time, not at
    # notify time. (Per Global Invariants #11; under-counting is the failure mode the
    # operator just hit with 5 orphans against ticket #246.)
    if ks.session_source == "created":
      increment session_create_attempts in lifecycle log entry for <ticket>
    # Tripwire: kickoff must never resolve to the orchestrator's own session.
    if ks.session_id == <ctx.sessionID>:
      surface "BLOCKED: KICKOFF_RESOLVED_TO_SELF" verbatim
      pause the batch
    # Tripwire: kickoff must bind the new/reused session to <directory> AND <agent>.
    # The plugin's session_kickoff checks both fields post-create so a silent
    # server-side drift (build ignores ?directory=) surfaces as a hard stop, not
    # as the coder landing in the wrong cwd and failing scripts/checkout-contract.sh.
    if not ks.directory_match:
      surface "BLOCKED: KICKOFF_DIRECTORY_BIND_FAILED" verbatim (ks.manualRecovery or the envelope's curl snippet)
      pause the batch
    if not ks.agent_match:
      surface "BLOCKED: KICKOFF_AGENT_BIND_MISMATCH" verbatim (ks.manualRecovery or the envelope's curl snippet)
      pause the batch
    record {
      directory, branch: branch_name, abbrev,
      session_id: ks.session_id, session_source: ks.session_source, resolution: ks.session_source,
      directory_match: ks.directory_match, agent_match: ks.agent_match,
      kickoff: ks.admitted ? "admitted" : "failed",
      session_create_attempts: <incremented value>,
    }
    # Envelope shape (informational; admitted: true is the only success gate):
    #   { ok, action: "kickoff", session_id, session_source: reused|created, resolution: reused|created,
    #     reused: <bool>, agent_match: <bool>, directory_match: <bool>, admitted: <bool>, status,
    #     target_directory, agent, error, manualRecovery }
    if not ks.admitted:
      # Advisory for the batch (do NOT pause other tickets) — but NEVER silent:
      # relay the envelope's manualRecovery to the user immediately:
      #   notify user: "Kickoff failed for #<n>: <ks.manualRecovery>"
      # (recovery: re-call session_kickoff directly, or the user opens the GUI session
      #  at <worktree dir> and types any message — ticket-lifecycle §0 reconstructs
      #  from GitHub)
      # The poller scripts/dev-loop-poller.sh + dev-loop-watch.sh will detect
      # the ticket_report: comment regardless of how the ticket was kicked.

  # 5b. wait for terminal reports (one per ticket in batch)
  #     wakes come from: (i) session_notify terminal-report injection (primary),
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
develop_session_id: <ctx.sessionID>     # the develop orchestrator's session id — coder uses this for the terminal session_notify injection
Load skill ticket-lifecycle and begin. The GitHub issue body (opencode-task-yaml) is the source of truth for stages[], acceptance, and test commands. Do not ask for a pasted brief; reconstruct anything missing per ticket-lifecycle §0 Bootstrap.
```

Compose it once per ticket; pass it verbatim to `session_kickoff` as `message`. The plugin does scoped-list-then-reuse-or-create-then-inject atomically (never falls back to the unfiltered global session list — that path caused the self-resolve bug). The `kickoff` returns `session_source: reused|created` and `resolution: reused|created` so the orchestrator can audit which path was taken; the orchestrator's only success gate remains `admitted: true`. No brief file is written; the kickoff message is the contract.

### §5b. Wake contract

- After kicking the batch, **end the turn**. Wakes (in priority order):
  1. **In-session `session_notify`** — when a coder session posts its terminal report, the develop orchestrator receives an injected message and runs the PR-approval gate for that ticket.
  2. **Poller `DEV_LOOP_WAKE`** — `scripts/dev-loop-poller.sh` (server-host cron) detects `ticket_report:` comment deltas and wakes the develop orchestrator.
  3. **Any user message** — dispatch a `developer` Task (`load: minimal`) to run `scripts/dev-loop-watch.sh`, process deltas, then handle the message.
- Wake contract: incoming message begins with `DEV_LOOP_WAKE: { repo, feature, reason }` → dispatch a `developer` Task (`load: minimal`) to run `scripts/dev-loop-watch.sh`; if no active loop for that feature is in the lifecycle log, ignore (idempotent — "ignore if not yours").

### §5c. PR-approval gate

For each `READY_FOR_HUMAN_REVIEW` (received via `session_notify` or by parsing the latest `ticket_report:` comment from `scripts/dev-loop-watch.sh`):

```text
notify user: "Ready for ticket review: <pr_url>"   # ONLY HUMAN GATE
wait for user: "ticket reviewed" (or user has already merged, including via GitHub UI — watch script handles the state transition + cleanup, see §5e)
```

> **Idempotency guard:** if the most recent `ticket_report:` (or poller-driven `DEV_LOOP_WAKE`) for the same `<repo>#<n>` has already been surfaced in this session, skip the notify and the wait — the operator is mid-review and the second surface is noise.

### §5d. Merge + cleanup

After user approval reply (or after out-of-band merge detection per §5e):

1. **Mark `state:ticket-reviewed`** (delegated `developer` Task):

   ```bash
   bash "$OC/scripts/issue-state-transition.sh" "<repo>" "<issue_number>" state:ticket-reviewed
   ```

   `state:ticket-reviewed` is the explicit "human approved this sub-PR" label — `state:ready-for-ticket-review` plus `state:ticket-reviewed` are both present between human approval and the merge completing. Idempotent on re-entry.

2. **Merge the sub-PR** — delegated `developer` Task with **the exact worktree/repo directory and `cd`/`git -C` in the prompt** (fixes the inherited-cwd failures from the old task-tool dispatch path):

   ```text
   cd <feature worktree directory>
   gh pr merge <pr_url> --squash --delete-branch=false
   ```

   On failure: surface `gh pr view --json mergeable` verbatim, pause the batch. On success: continue.

3. **Fast-forward the feature branch** in the feature worktree (delegated `developer`, `cd <feature worktree dir>`). The `git merge --ff-only origin/opencode/feat-<slug>` self-ff MUST be guarded by `scripts/assert-merge-cwd.sh` (develop-pollution guard — see §12). On any `BLOCKED: *` exit, surface verbatim and pause:

   ```bash
   cd <feature worktree directory>
   ASSERT_MERGE_CWD="<feature worktree dir>" \
   ASSERT_MERGE_BRANCH="opencode/feat-<slug>" \
   ASSERT_MERGE_REF="origin/opencode/feat-<slug>" \
   ASSERT_REPO="<OWNER/REPO>" \
   ASSERT_BRANCH_CONTEXT="feature-worktree" \
     source "${OPENCODE_CONFIG:-$HOME/.config/opencode}/scripts/assert-merge-cwd.sh"
   git fetch origin "opencode/feat-<slug>"
   git merge --ff-only "origin/opencode/feat-<slug>"
   ```

4. **Delete the ticket worktree** — dispatch `worktree-manager` `delete { directory: <ticket worktree dir> }`.

5. **Delete the remote ticket branch** — delegated `developer`: `git push origin --delete opencode/ticket-<n>-<slug>-<abbrev>` (developer is the only delegated actor for `git push origin --delete`; coder session itself never runs this).

6. **Re-batch (per-merge next-wave).** Re-running `dev-loop-batch.sh` after every merge is what unlocks dependent tickets promptly (`scripts/dev-loop-batch.sh:151-156` already treats a merged sub-PR as dep-satisfied, so the exit code tells you whether new runnable tickets are now available):
   1. Delegated `developer` (`load: minimal`): re-run `bash "$OC/scripts/dev-loop-batch.sh" <slug>`.
   2. Exit 2 → surface stderr verbatim, stop (never "all done").
   3. Exit 0 → for each entry **not already present in the lifecycle log with a recorded `directory`** (the in-flight skip-guard), run the §5-0 freshness gate → `create_ticket` (§5a-i) → `KICKOFF_ALREADY_DELIVERED` precheck (§5a-iii) → `session_kickoff` (§5a-iv). Skipping already-live tickets is mandatory: re-running `create_ticket` for a live ticket trips `worktree-manager` Hard Rule 4 and produces a `-2` sibling worktree.
   4. Exit 1 → if any ticket in the lifecycle log is still in flight (kicked, no terminal report, or reported but not yet merged), **end the turn and keep waiting** — do not go to §8. Only when exit 1 AND the in-flight set is empty AND no `BLOCKED` ticket exists, go to §8.
   5. End the turn after kicking (§5b wake contract unchanged).

   The `KICKOFF_ALREADY_DELIVERED` (§5a-iii) precheck **must still run** for every ticket entry even when the in-flight skip-guard fires — it is the durable-comment safety net for tickets whose coder crashed mid-kickoff (lifecycle log says "kicked" but the `ticket_report:` comment is missing).

### §5e. Out-of-band merges (GitHub UI)

If the user merges the sub-PR via GitHub UI instead of the gate: `scripts/dev-loop-watch.sh` flags `out_of_band_merged: true` on the ticket entry (PR state MERGED while the issue label still reports a pre-merge state), the poller or user message wakes the develop orchestrator. The orchestrator then:

1. Confirms via a delegated `developer` Task (`gh pr view --json state`).
2. Transitions the ticket to `state:ticket-reviewed` so the label matches reality (delegated `developer` runs `scripts/issue-state-transition.sh <repo> <n> state:ticket-reviewed`) — matches the new semantic: "merged into feature branch" == "human approved".
3. Runs the **full** §5d sequence from step 3 onward: fast-forward the feature branch → delete ticket worktree → delete remote branch → re-batch (§5d step 6). Out-of-band merges MUST NOT skip the ff — the §5-0 gate's only safety property is that the local feature ref is up to date, and the ff is what makes that true. Skipping it leaves the next ticket worktree forking off pre-merge code.

## §6 State transitions inside the loop

The coder session owns `state:in-progress` (set during `ticket-lifecycle` §0 Bootstrap) and `state:ready-for-ticket-review` (set when the sub-PR opens, after `code_review_gate:` is posted). The develop orchestrator owns `state:ticket-reviewed` (set on "ticket reviewed" reply or detected out-of-band merge, immediately before sub-PR merge into the feature branch) and `state:done` (set on "all reviewed" reply, immediately before the feature PR merges to `develop`). The feature coder owns `state:ready-for-feature-review` (set on every child ticket after it opens the feature PR — see `skills/feature-review/SKILL.md` §5). `state:blocked` is owned by whichever actor surfaced the blocker (coder or orchestrator). All transitions go through `scripts/issue-state-transition.sh <repo> <n> <state>` delegated to `developer`.

## §7 Failure handling

| Failure | Where it surfaces | Response |
|---|---|---|
| `worktree-manager` returns `blocker_code` | develop orchestrator loop | Surface verbatim, stop, do not retry. |
| `worktree-manager` returns `WORKTREE_TOOLS_NOT_REGISTERED` | develop orchestrator loop | The worktree plugin is not loaded in this environment. Surface `next_action` verbatim and stop: deploy `plugins/worktree.js` into the config `plugins/` dir, restart opencode-server, confirm the boot log shows `[worktree-plugin] loaded` before retrying. |
| `session_kickoff` returns `ok: false, blocker_code: "SESSION_API_FAILED"` (advisory only) | develop orchestrator loop | Relay the envelope's `manualRecovery` to the user IMMEDIATELY (never silent); record advisory in lifecycle log; the kickoff message is the contract and the coder session can still bootstrap from the branch + GitHub. **Do not pause the batch.** The `session_kickoff` default `create_if_absent: true` no longer surfaces a "no session" code — an empty scoped list now means "create", not "fail". Operators that need the "create not allowed" semantics must pass `create_if_absent: false` and read the `NO_SESSION_FOR_WORKTREE` `blocker_code` from that envelope. |
| `session_kickoff` returns `ok: false, blocker_code: "NO_SESSION_FOR_WORKTREE"` (only when `create_if_absent: false`) | develop orchestrator loop | Surface verbatim and pause the batch. Caller opted out of the auto-create; no session exists for the directory and the operator must intervene. |
| `session_kickoff` returns `admitted: false` without a `blocker_code` (advisory only) | develop orchestrator loop | Relay `manualRecovery` to the user IMMEDIATELY; record advisory; re-call `session_kickoff` directly (no subagent), or the user opens the GUI session and types anything. **Do not pause the batch.** |
| `session_notify` returns `error: "session_not_found"` (e.g. stale `develop_session_id` after a restart) | develop orchestrator loop (inbound wake from coder) | The `ticket_report:` / `feature_report:` issue comment is the **mandatory durable channel**; `scripts/dev-loop-poller.sh` + `scripts/dev-loop-watch.sh` will wake the develop orchestrator within one poll interval. Do not retry inject; continue waiting for the durable wake. (Coder-side counterpart: the coder emits the `session-notify-fallback` block — see `skills/orchestrate/session-notify-fallback.md` — when its outbound notify hits this shape.) |
| `session_kickoff` returns `session_id == <ctx.sessionID>` (`BLOCKED: KICKOFF_RESOLVED_TO_SELF`) | develop orchestrator loop (tripwire per Global Invariants #8) | Pause the batch and surface `BLOCKED: KICKOFF_RESOLVED_TO_SELF` verbatim. This indicates a regression — `session_kickoff` resolved to the orchestrator's own session instead of creating/reusing one for the worktree directory. Investigate `plugins/session-manager.js` (scoped list filter, agent match) before retrying. Should never fire post-fix. |
| `session_kickoff` returns `directory_match: false` (`BLOCKED: KICKOFF_DIRECTORY_BIND_FAILED`) | develop orchestrator loop (tripwire per Global Invariants #9; hard stop, not advisory) | Pause the batch and surface `BLOCKED: KICKOFF_DIRECTORY_BIND_FAILED` verbatim along with the envelope's `manualRecovery` curl snippet. The kickoff landed the coder in the wrong cwd — `scripts/checkout-contract.sh --verify` would reject it. Indicates `plugins/session-manager.js` `session_create` returned a stored `directory` that did not match the requested worktree dir (server ignored `?directory=`). Investigate `plugins/session-manager.js` before retrying. Should never fire post-fix. |
| `session_kickoff` returns `agent_match: false` (`BLOCKED: KICKOFF_AGENT_BIND_MISMATCH`) | develop orchestrator loop (tripwire per Global Invariants #9; hard stop, not advisory) | Pause the batch and surface `BLOCKED: KICKOFF_AGENT_BIND_MISMATCH` verbatim along with the envelope's `manualRecovery` curl snippet. The new session was bound to a different agent than requested (the coder would load the wrong agent prompt). Investigate `plugins/session-manager.js` `session_kickoff` create branch before retrying. Should never fire post-fix. |
| `session_report:` arrives without `bind_failed: false` for that `session_id` in the lifecycle log (`BLOCKED: KICKOFF_BIND_CONFIRMATION_MISSING`) | develop orchestrator loop (Global Invariant #10) | Pause the batch and surface verbatim. The kickoff silently admitted without bind evidence; the coder may be in the wrong cwd. Inspect the kickoff envelope and the develop-loop-watch output, then dispatch a `developer` Task to re-run `scripts/checkout-contract.sh --verify` against the worktree before retrying. |
| §5a-iii `KICKOFF_ALREADY_DELIVERED` precheck returns a `ticket_report:` comment id for the issue | develop orchestrator loop (orchestrator-owned precheck, was worktree-manager step 2a) | Pause the batch and surface verbatim. The coder already finished and posted the durable terminal report; re-kicking would create an orphan. Inspect the `ticket_report:` comment on the issue and resume from `ticket-lifecycle` §0 if the coder is alive (or treat the ticket as done and move to PR-approval if the coder has merged). Do not retry the kickoff — that is exactly what this check exists to prevent. |
| `session_kickoff` create branch ran `session_create_attempts` times against the same worktree (`BLOCKED: WORKTREE_SESSION_ATTEMPTS_EXCEEDED`) | develop orchestrator loop (Global Invariant #11; hard stop, not advisory) | Pause the batch and surface verbatim. The develop loop has hit the per-worktree session-create ceiling (default `3`, configurable via `session_create_cap`). The worktree likely has orphaned sessions registered against it from prior kickoff storms (this is the failure mode the operator hit — 5 orphans against ticket #246 before the loop paused). Operator intervention is required: dispatch `worktree-manager.recover { directory }` to deregister the orphan sessions via the sanctioned `rewrite-worktree-gitdirs.py` + `session_delete` flow, then either raise `session_create_cap` in the lifecycle log or skip the offending ticket. Do not retry the kickoff automatically. |
| `worktree-manager.create_ticket` step 8.5 readiness check fails (`BLOCKED: WORKTREE_PREFLIGHT_FAILED`) — worktree not reachable / not writable / `branch_local_up_to_date === false` / `parent_branch_merged === false` | develop orchestrator loop (Global Invariant #12; hard stop, not advisory) | Pause the batch and surface `BLOCKED: WORKTREE_PREFLIGHT_FAILED` verbatim along with the captured `branch_local_head_sha` vs `origin/<feature_branch>` SHAs and the envelope's `manualRecovery`. **Do not retry by re-running `create_ticket`** — Hard Rule 4 would suffix `-2` on the worktree name and create a sibling. Inspect the worktree (likely a wrong-ref reset that left the worktree on `develop`/`main` instead of the feature branch; or the feature branch has not been pushed yet). If the feature ref is stale, dispatch a `developer` Task (`load: minimal`) to run the §5-0 freshness gate (fetch + rev-parse + one auto-ff repair attempt) — never reset the worktree branch directly; if the parent is unmerged, the upstream ticket likely needs to merge first. The `branch_local_up_to_date === false` branch is the canonical signal of the latent #245 reset-to-wrong-ref bug. |
| `scripts/dev-loop-batch.sh` exits 1 | develop orchestrator loop | All tickets done AND no in-flight tickets remain → exit loop, go to §8. If any ticket in the lifecycle log is still in flight (kicked, no terminal report, or reported but not yet merged), keep waiting — do not advance to §8. |
| `BLOCKED: FEATURE_BRANCH_STALE` (§5-0 gate; both after the initial §5 batch run and after every §5d step 6 re-batch) | develop orchestrator loop | Surface the local `refs/heads/opencode/feat-<slug>` SHA and the `refs/remotes/origin/opencode/feat-<slug>` SHA verbatim, pause the batch, do NOT call `create_ticket`. If `feature_worktree_gone: true` is in the envelope, the feature worktree is missing — recreate it via `worktree-manager.create_feature` before continuing (do not skip; the orchestrator's only handle on the feature ref is through that worktree). **Never** `git reset --hard` the feature branch as a workaround and **never** fork a ticket off `develop`/`main` to bypass the gate — both defeat the freshness guarantee. Recovery: confirm the sub-PR actually merged into `opencode/feat-<slug>` on GitHub, then re-run the §5-0 gate (which attempts one automatic `git merge --ff-only` repair before surfacing this code again). The 8.5 in-worktree-manager readiness check `branch_local_up_to_date === false` is a *post-create* tripwire for the same latent #245 wrong-ref bug; keep both, document that 8.5 alone is no longer the only detector. |
| `scripts/dev-loop-batch.sh` exits 2 | develop orchestrator loop | gh/API failure — surface stderr verbatim, stop. Never treat as "all tickets done" (an empty lifecycle log + exit 2 is a transport failure, not completion). |
| Ticket `BLOCKED: ENV_BLOCKED` after one repair | coder session → develop orchestrator | Surface `recommended_env_fix`, pause batch. |
| Ticket `BLOCKED: STABILIZATION_EXHAUSTED` (CI fail after 3 iterations) | coder session | Surface verbatim, pause batch. |
| Ticket `BLOCKED: CROSS_TICKET_REVIEW` | coder session | Surface verbatim, route to the feature coder's remediation flow (`feature-review` §8) — pause the batch until the feature coder creates `remediation:` issues and the orchestrator re-batches. |
| Ticket `BLOCKED: FALLBACK_EXHAUSTED` | coder session | Surface verbatim, pause batch. |
| Sub-PR merge fails (branch protection / conflict) | develop orchestrator | Surface `gh pr view --json mergeable`, pause batch. |
| Remote-branch delete fails (protected / already gone) | develop orchestrator cleanup | Non-fatal: log, continue. Surface as advisory at feature close. |
| User merges sub-PR themselves | develop orchestrator | `gh pr view --json state` (delegated `developer`) confirms MERGED; proceed to worktree + remote-branch cleanup. |
| User says "happy" but PR not yet merged | develop orchestrator | Orchestrator merges the sub-PR (delegated developer, with explicit `cd`/`git -C`), then cleanup. |
| In-session `session_notify` delivery fails (`develop_session_id` stale) | coder session → develop orchestrator | The `ticket_report:` comment is the mandatory durable channel; the poller will wake the develop orchestrator within one poll interval. |
| Poller disabled / down | develop orchestrator | `scripts/dev-loop-watch.sh` is still agent-invocable; the user can manually trigger a wake. |
| Sync-claim verification (§12) reflog or `gh pr list --base develop` check fails (`BLOCKED: DEVELOP_POLLUTION_DETECTED`) | develop orchestrator (sync-claim gate) | Surface the offending reflog entry or merged PR (number + `headRefName` + `mergedAt`) verbatim, pause, ask operator for next steps. **Never** rebase, **never** reset, **never** auto-fix — operator decides after human review of polluted commits. The script (`scripts/assert-merge-cwd.sh`) and branch protection are the upstream guards; this gate is the post-hoc detector. |

## §8 Feature coder kickoff + feature merge

After `scripts/dev-loop-batch.sh` exits 1 and there are no `BLOCKED` tickets, every ticket has merged into `opencode/feat-<slug>`. **Kick the feature coder** (same `coder` agent, loading `feature-review`) in the feature worktree via direct `session_kickoff`:

```text
session_kickoff {
  directory: <feature worktree directory>,
  agent: "coder",
  message: <pointer: feature slug, feat branch, "Load skill feature-review and begin">
}
```

End the turn after kicking. Do not poll. The feature coder owns the entire verification loop end-to-end (test suite, code-review gates, difficulty gates, docs, `state:ready-for-feature-review` on every ticket, feature PR, bounded stabilization) and posts one `feature_report:` comment on the PRD parent + best-effort `session_notify` back here. The develop orchestrator owns `state:done` (set after human "all reviewed") and the feature PR merge — see §8a/§8c.

### §8a. On `feature_report:` wake

When the feature coder wakes you (via `session_notify` or poller or user message), read the terminal `feature_report:` status. You do **not** re-verify code-review or CodeRabbit evidence — every verification gate already ran inside the coder sessions; the terminal report plus the human approval below are your only gates.

- `READY_FOR_HUMAN_REVIEW` → **first** verify every child ticket of `feature:<slug>` carries `state:ready-for-feature-review` (delegated `developer` Task: `gh issue list -l "feature:<slug>" --state all --json number,labels` — filter to entries whose labels include `state:ready-for-feature-review`; the count must equal the total child-issue count). If any child is missing `state:ready-for-feature-review`, surface `BLOCKED: STATE_FEATURE_REVIEW_INCOMPLETE` with the offending ticket numbers and pause — do not advance to §8b. Capture `pr_url` and continue to §8b once verified.
- `BLOCKED: FEATURE_REMEDIATION` with `remediation:` issue numbers → re-batch those issues through the normal ticket pipeline (§5 batch loop); when they merge, kick the feature coder again.
- Any other `BLOCKED` → surface verbatim and pause the loop.

### §8b. Human gate

On READY (and verified every child carries `state:ready-for-feature-review`), print exactly:

```text
Ready for feature review: <pr_url>

state:ready-for-feature-review is set on every ticket; say "all reviewed" to mark every ticket state:done and merge the feature PR (squash, --delete-branch=false).
```

Then wait for the user's "all reviewed" message. Do not auto-merge.

### §8c-i. Mark every child ticket `state:done`

For every child ticket of `feature:<slug>`, dispatch a `developer` Task (`load: minimal`) to run:

```bash
bash "$OC/scripts/issue-state-transition.sh" "<repo>" "<issue_number>" state:done
```

`state:done` is the final accept label — set by the develop orchestrator (not the feature coder) after human "all reviewed" on the feature PR. Issues **stay open** until spec `feature-complete`. Skip tickets already `state:done`. For large N, dispatch one `developer` Task with an explicit bash loop over `gh issue list -l "feature:<slug>" --state all --json number` rather than N separate Tasks (mirrors the `feature-review` §5 pattern).

### §8c-ii. Merge the feature PR

After `state:done` is set on every ticket, dispatch a `developer` Task (`load: minimal`) with explicit `cd <feature worktree dir>` (and `git -C`). The merge uses `gh pr merge` (the only legal feature→develop path — see §12); the develop-pollution guard is sourced first as a tripwire so a future edit that swaps to `git merge` is caught immediately:

```bash
cd <feature worktree directory>
ASSERT_MERGE_CWD="<feature worktree dir>" \
ASSERT_MERGE_BRANCH="opencode/feat-<slug>" \
ASSERT_MERGE_REF="origin/opencode/feat-<slug>" \
ASSERT_REPO="<OWNER/REPO>" \
ASSERT_BRANCH_CONTEXT="feature-worktree" \
  source "${OPENCODE_CONFIG:-$HOME/.config/opencode}/scripts/assert-merge-cwd.sh"
gh pr merge <pr_url> --squash --delete-branch=false
```

On `BLOCKED: *` exit: surface verbatim, pause. On failure: surface `gh pr view --json mergeable` verbatim, pause. On success: continue to §8d.

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

All worktree lifecycle (create, list, delete, reset) is delegated to the `worktree-manager` subagent, which calls the `worktree_*` tools registered by `plugins/worktree.js`. **Raw git worktree subcommands (`worktree add`, `worktree remove`, `branch opencode/...`) are forbidden** — they bypass GUI registration and are not coordinated with session start. Session messaging (kickoff, terminal-report notify) is direct: the orchestrator calls `session_kickoff` / `session_list` / `session_notify` via the `session_*` plugin tools registered by `plugins/session-manager.js`. There is no `session-manager` subagent.

Restart / recovery for stuck worktrees (post `opencode-server` restart, stale state): dispatch `worktree-manager` `reset { directory }`. If worktrees are stuck in the GUI / `worktree_list` after a failed delete (WorktreeNotGitError), dispatch `worktree-manager` `recover { directory }` — the system's sanctioned `rewrite-worktree-gitdirs.py` + `session_delete` (called directly by worktree-manager, not via a subagent). Never raw `git worktree`.

## §11 Hand-off markers

| Marker | Emitted by | Consumed by |
|---|---|---|
| `feature_report:` (issue comment on PRD parent) | feature coder on terminal report | develop orchestrator reads the status: READY → §8a verify + §8b human gate + §8c-i state:done + §8c-ii merge; `FEATURE_REMEDIATION` → re-batch `remediation:` issues; other BLOCKED → surface + pause |
| `READY_FOR_HUMAN_REVIEW` | coder session when sub-PR is green and comment-clean (ticket mode) | develop orchestrator surfaces to user (single human gate per PR); reply "ticket reviewed" → §5d marks `state:ticket-reviewed` then merges |
| `BLOCKED` | coder session on environment-after-repair, CI-exhaustion, fallback-exhaustion, or cross-ticket review | develop orchestrator surfaces verbatim and pauses the batch |
| `ticket_report:` (issue comment) | coder session on terminal report (ticket mode) | develop orchestrator's `scripts/dev-loop-watch.sh` + `scripts/dev-loop-poller.sh` — durable wake channel and out-of-band merge detector; the `ticket_report:` body is the canonical durable channel for the review-ready signal even when `session_notify` fails |
| `DEV_LOOP_WAKE: { repo, feature, reason: TICKET_REVIEW_READY \| FEATURE_REVIEW_READY }` | poller (`scripts/dev-loop-poller.sh`) when `ticket_report:` / `feature_report:` delta detected, or manual operator fallback via `gh issue comment` (see `skills/orchestrate/session-notify-fallback.md`) | develop orchestrator; ignored if no active loop for that feature. `TICKET_REVIEW_READY` → §5c surface; `FEATURE_REVIEW_READY` → §8a verify + §8b gate. |

There is no ticket-dispatch marker — the coder session is the auto-started GUI session for the worktree, not a `task`-tool dispatch. The `session_notify` plugin tool injects report-back messages into an existing session via `POST /session/{id}/prompt_async`; it does not dispatch a new subagent.

## §12 Sync-claim verification gate (develop-pollution detector)

> **Origin:** 2026-09-02 incident — a developer Task ran `git merge
> origin/opencode/feat-workflow-runtime` (local fast-forward) inside the
> `develop` main checkout, polluting develop with feature work that should
> have only landed via a reviewed PR. Develop reflog: `fdfef0a
> develop@{2026-09-02 16:07:12 +0000}: merge
> origin/opencode/feat-workflow-runtime: Fast-forward`. No PR with
> head=feat-workflow-runtime, base=develop ever existed. Branch protection
> on develop was off.

The develop branch is the canonical shared ref. Any time a user message
contains a sync-claim phrase — "branches are in sync", "in sync", "aligned",
"up to date", "all good on develop", or any equivalent — the orchestrator
MUST verify before advancing. The script (`scripts/assert-merge-cwd.sh`,
sourced before any `git merge`) and GitHub branch protection on develop are
the upstream guards; this gate is the post-hoc detector that catches any
pollution that already landed.

**Sync-claim phrases** (case-insensitive substring match on the user's most
recent message):

| Phrase (any of) |
| --- |
| `in sync` / `are in sync` / `branches are in sync` |
| `aligned` / `all aligned` |
| `up to date` / `up-to-date` |
| `all good on develop` / `develop is clean` |
| `develop is up to date` / `develop is in sync` |

**Verification** — dispatch ONE `developer` Task (`load: minimal`):

```text
Task developer load: minimal
bash -c '
  cd <repo root of the impl repo>
  echo "=== reflog develop (head -10) ==="
  git reflog show develop | head -10
  echo "=== merged PRs base=develop (head -20) ==="
  gh pr list --base develop --state merged -L 20 \
    --json number,headRefName,mergedAt
  echo "=== open PRs base=develop (head -20) ==="
  gh pr list --base develop --state open -L 20 \
    --json number,headRefName,createdAt
'
```

**Hard-stop with `BLOCKED: DEVELOP_POLLUTION_DETECTED` if EITHER:**

(a) the reflog shows any `merge origin/opencode/*` or `merge: Fast-forward`
of an `origin/opencode/*` ref within the last N=10 entries (whether
fast-forward or not), OR

(b) any merged or open PR's `headRefName` matches `^opencode/feat-`.

Surface the offending entry (full reflog line OR PR number + `headRefName` +
timestamp) verbatim. Do **NOT** advance and do **NOT** offer "I'll rebase
around it" or "I'll reset develop" — the operator must decide after human
review of the polluted commits. After surfacing the BLOCKED line, ask the
operator for next steps (typical recovery: `git fetch && git reset --hard
origin/develop` to a known-clean SHA, then re-merge the feature PRs
properly through `gh pr merge` after the human "all reviewed" gate).

**Allowed edge cases** that MUST NOT trip the gate:

- `git fetch` / `git pull` entries in the reflog (these are not merges).
- `merge origin/develop` in the reflog (develop syncing with develop).
- Rebase / cherry-pick / commit entries in the reflog (not merges).
- Open or merged PRs whose `headRefName` is `opencode/ticket-<n>-...`
  (sub-PRs merge into the feature branch, not develop — those are legal).
- `feature-report` / `ticket-report` issue-comment activity (irrelevant to
  the reflog/PR-list check).

**The sync-claim gate is mandatory, not advisory.** Treat the user's
sync-claim as untrusted input until the verification completes. This is the
detection layer for a class of bugs the upstream guards (script + branch
protection) cannot fully prevent (e.g. an agent that bypasses the script
entirely, or a manual `git push --force` that the protection rule allows
for admins).

## Hard rules for the develop orchestrator

- Never call `worktree_*` tools directly — delegate to `worktree-manager`.
- **One worktree op per `worktree-manager` Task.** Every `create_feature` / `create_ticket` / `delete` / `reset` call is its own Task — one op, one Task, one round-trip. If the user names N worktree ops in a single message (e.g. "create a feature worktree and two ticket worktrees"), dispatch N separate `worktree-manager` Tasks **in order**, each as its own `developer`-style dispatch with idempotent pre-checks (does the worktree already exist? if yes, exit fast). Never chain multiple `worktree_*` calls inside a single Task. Rationale: a hang or slow call in one chained op silently truncates the rest with no error payload; sequential one-per-Task dispatches stay sub-second on a warm daemon (measured: 3 creates ≈ 3.1s) and each emits a clean envelope on failure. If you spot a chained-worktree pattern in a user message or draft dispatch, flag it and split before acting.
- **Session messaging is direct.** `session_kickoff` and `session_notify` are plugin tools you call directly — there is no `session-manager` subagent to dispatch. The §5 loop calls `session_kickoff` per ticket, then waits for terminal reports that arrive via `session_notify` (in-session) or the poller.
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
- `skills/feature-review/SKILL.md` — the feature coder's verification + sign-off loop (same `coder` agent, different skill).
- `agents/worktree-manager.md` — `create_ticket` accepts `feature_branch` (the captured §4 branch) as the safety link.
- `plugins/worktree.js` — `worktree_create_feature` / `worktree_create_ticket` / `worktree_list` / `worktree_delete` / `worktree_reset`.
- `plugins/session-manager.js` — `session_create` / `session_list` / `session_notify` / `session_kickoff` / `session_delete`. The orchestrator holds `session_kickoff` + `session_list` + `session_notify` directly; `worktree-manager` holds `session_delete` for `recover`.