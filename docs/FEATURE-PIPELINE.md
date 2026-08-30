# Feature pipeline

Spec-driven path from PRD to merge. You choose only **architect** or **orchestrate**; open the right repo; for architect start with **`hi`** and pick the menu line shown. Shell bootstrap once (`setup-project`); after that, use OpenCode menus.

User overview (diagram + how-to): [../README.md#feature-flow-prd--sign-off](../README.md#feature-flow-prd--sign-off).

## Flow (what you do)

| Stage | Repo | Select | Your choice | Your job | This stage owns |
|-------|------|--------|-------------|----------|-----------------|
| Plan / PRD | **spec** (`*-spec`) | **architect** → `hi` | **1. Product feature / PRD — …** | Answer grill; **approve** `docs/prd/<slug>.md`; **approve** issue plans | Planning + per-work-repo handoffs only — not code, not PR polish |
| Build | **each work repo** | **orchestrate** on `develop` (new session) | Paste handoff / `feature:<slug>` | Wait until the feature PR exists | Develop orchestrator owns `opencode/feat-<slug>` + per-ticket worktrees; for each ticket it dispatches `worktree-manager create_ticket` with `kickoff_agent: "coder"` + `kickoff_message`. The plugin writes `<worktree-gitdir>/opencode-ticket-brief.json` and injects the kickoff into the auto-started GUI session via `session.promptAsync`. That auto-started session IS the **coder** primary agent (loading `ticket-lifecycle`), self-bootstraps from the brief file + GitHub, runs every `stages[]` entry + sub-PR stabilization, and posts one `ticket_report:` comment. |
| Review / accept / docs / merge | **same work repo, feature worktree** | **architect** (new session) → `hi` | **4. Review / sign-off — Mode F …** then **R.** / **1.** / **2.** | Drive review; when happy: **Phase 1** (`state:done`, tickets stay open) then **Phase 2** docs; **merge gate** with human confirmation | **All PR readiness, ticket acceptance, and feature-PR merge.** Work-repo architect is where you sign off the work before spec |
| Remediation loop | **same work repo** | **orchestrate** ↔ **architect** | After **R**, if changes needed: **orchestrate** again → then architect → **4** → **R** again | Stay in the work repo until you are happy | Loop until Merge-ready — **do not go to spec yet** |
| Final close | **spec** | **architect** → `hi` | **3. Feature complete — …** | Only after **every** work repo finished Mode F; choose human vs agent **merge gate** | **Merge + close only:** close tickets already `state:done`, merge PRs, close PRD. Spec does **not** re-do review or PR prep |

Shape:

```text
SPEC (start)          WORK REPO develop (build → review → fix → review)   SPEC (finish)
architect / 1    →    develop orchestrator (develop branch)               architect / 3
                       └─→ create_ticket + kickoff coder (per ticket, auto)
                            (auto-started GUI session IS the coder session;
                             brief file in <gitdir> + GitHub = source of truth)
                            (sub-PRs self-stabilize inside the coder session)
                       └─→ sub-PRs merge into opencode/feat-<slug>
                       →  architect / 4 (in feature worktree)
                          Phase R → Phase 1 (state:done) → Phase 2 docs → merge gate
PRD + handoffs        build → review → (fix → review)*                  merge + close
```

### Develop-loop details (orchestrator → coder split)

- The **develop orchestrator** (`orchestrate`) is the *only* persistent session in the impl repo. It lives in the `develop` branch, owns all `worktree-manager` calls and remote-branch deletes, and never executes tickets itself. For each runnable ticket it dispatches `worktree-manager create_ticket` with `kickoff_agent: "coder"` + `kickoff_message`; the plugin writes `<worktree-gitdir>/opencode-ticket-brief.json` and injects the kickoff message into the auto-started GUI session via `session.promptAsync`. There is **no** `task`-tool ticket dispatch — subagents would inherit the develop cwd and `scripts/checkout-contract.sh --verify` would reject them.
- **Coder sessions** are auto-started GUI sessions for each ticket worktree, running the `coder` primary agent loading `ticket-lifecycle`. They own the full inner loop: §0 Bootstrap (read brief file via the read tool + reconstruct from GitHub) → silent preflight (delegated `developer` Task; resolves the compose test backend — `compose_test_file: none` → `BLOCKED: ENV_BLOCKED`) → every `stages[]` entry (test-writer RED → owner GREEN → per-stage focused code-review) → **final `all_stages: true` full-suite gate via `docker-compose.test.yml`** → sub-PR open → PR stabilization (max 3 iterations) → tear down the compose backend → one terminal `ticket_report:` comment (mandatory durable channel) + best-effort `session_notify` to `develop_session_id`. Mid-stage escalation to `senior-dev` is unattended (no operator confirmation — the only human gate is PR review); provider fallback (`kilo-fallback` → `openrouter-fallback`) is layered on top for failed children with a complete `fallback_context`.
- The develop orchestrator merges each sub-PR after human approval, deletes the ticket worktree + remote ticket branch, and re-batches until `scripts/dev-loop-batch.sh` exits 1. Then it hands off to **architect / 4** inside the feature worktree (`architect-feature-signoff`) for full audit + CodeRabbit + accept + merge.
- The single human gate is **PR review** (one notification per sub-PR; one merge gate at the feature level). The develop orchestrator wakes on terminal reports via `session_notify` (in-session); out-of-band GitHub-UI merges are detected by `scripts/dev-loop-poller.sh` (server-host cron, ~2-min interval — see `docs/RUNBOOK.md`).

### Hard reminders

- Sign-off of the **work** (review, remediation, `state:done`, docs, PR merge-ready) = **architect in the work repo**.
- Sign-off of the **feature across the stack** (merge + close) = **architect in spec**, menu **3. Feature complete**.
- Spec merge closes **done-state** tickets; getting them to done and getting the PR ready is **work-repo** work.
- Do **not** run Mode F Phase R/1/2 in the spec repo for normal delivery (spec menu **4** is rare cross-repo assist only).

### Session boundaries (recommended)

- **Planning:** `cd` into **spec** → **architect** → `hi` → **1. Product feature / PRD …** (one session through handoffs). Example: `cd ~/code/myapp/myapp-spec`.
- **Build:** `cd` into each **work repo** → **new** session → **orchestrate** on the **`develop` branch** → paste `feature:<slug>` (parallel OK when handoff says so). The develop orchestrator creates `opencode/feat-<slug>` and dispatches bounded full-ticket Tasks. Example: `cd ~/code/myapp/myapp-web`.
- **Review loop (stay in work repo, feature worktree):** **new** session → **architect** → `hi` → **4. Review / sign-off — Mode F …** → **R. Phase R …** (run inside `opencode/feat-<slug>`, the feature worktree). If changes needed → **orchestrate** again → back to architect **4** → **R**. When happy → **1. Phase 1 …** then **2. Phase 2 …** then **merge gate**.
- **Complete:** back in **spec** → **architect** → `hi` → **3. Feature complete …** only after every work repo finished Mode F.

Same-session handoff is optional (`/compact` after a short table HANDOFF block); use a new session if the provider errors on tool history.

### Sign-off and ticket closure

| Label / state | Set when | Meaning |
|---------------|----------|---------|
| `state:in-progress` | During **orchestrate** in the work repo | Actively executing issue/stages |
| `state:ready-for-review` | After **orchestrate** finishes an issue | Implementation done; awaiting work-repo architect |
| `state:done` | Work-repo architect **Phase 1** | You accepted the work; issue **stays open** until spec merge |
| Issue **closed** on GitHub | Spec **3. Feature complete** at merge | Ticket complete |

**Orchestrate** does not accept tickets, write sign-off docs, close issues, or merge PRs. One **feature PR** per work repo after the queue is empty; then you move to work-repo architect for Mode F.

#### Mode F — three-phase sign-off (work repo only)

| You choose | Your job | Done when |
|------------|----------|-----------|
| **R. Phase R — review PR feedback…** | Review PR/CI/tickets/feedback; if more work → switch to **orchestrate**, then return here | Merge-ready (or remediation handoff) |
| **1. Phase 1 — accept issues…** | Accept only when Phase R is Merge-ready | Tickets `state:done` (**stay open**) |
| **2. Phase 2 — docs…** | Confirm doc scope when asked | Docs on the feature PR; PR merge-ready in this repo |

Skill detail: [skills/orchestrate/SKILL.md](../skills/orchestrate/SKILL.md) (develop orchestrator outer loop) and [skills/architect-feature-signoff/SKILL.md](../skills/architect-feature-signoff/SKILL.md) (feature-architect in `opencode/feat-<slug>`). The per-ticket inner loop lives in [skills/ticket-lifecycle/SKILL.md](../skills/ticket-lifecycle/SKILL.md), loaded by the `coder` primary agent.

#### Feature complete — merge gate (spec repo only)

| Step | Your job / outcome |
|------|-------------------|
| Rollup | Confirm every work repo has Mode F done (`state:done` open, PRs listed) |
| Merge gate | Choose human merge or agent merge on your behalf |
| Close + merge | Closes child issues that are already `state:done`; merges PRs; deletes head branches (never develop/main/master) |
| PRD | Closes parent + delivery record |

Skill detail: [skills/feature-complete/SKILL.md](../skills/feature-complete/SKILL.md).

#### Remediation (work-repo loop)

From Mode F **R**, if changes are needed: select **orchestrate** in the **same work repo** (prefer new session), then return to **architect** → `hi` → **4** → **R**. Repeat until happy. Issues stay open until Spec merge. **Do not** start feature-complete until this loop is done in every work repo.

## Execution mode

| Mode | Where | Source of truth | What you select |
|------|--------|-----------------|-----------------|
| **Spec / GitHub** (default) | spec + work repos | GitHub issues with `feature:<slug>` after planning | Spec **architect** → **1**; work **orchestrate**; work **architect** → **4**; spec **architect** → **3** |

Fanout alone is not enough for the stage loop — planning must finish issue-expand before **orchestrate** on the spec path. Orchestrate blocks at bootstrap if expansion is incomplete.

## One human shell command (stack bootstrap)

From the **project parent** (folder containing `*-spec` and work repos):

```bash
export GH_ORG=your-github-login-or-org
cd ~/code/APP && setup-project
```

`GH_ORG` is the GitHub **owner** (`owner/repo`), not the app slug or local folder name. That syncs tooling into spec + work repos. Everything else is OpenCode menus. See [RUNBOOK.md](RUNBOOK.md) and [skills/setup-project/SKILL.md](../skills/setup-project/SKILL.md).

**Project board (optional):** Set `GH_PROJECT` in `~/.opencode-agent-env` before publish/fanout. See [GITHUB-PROJECT-BOARD.md](GITHUB-PROJECT-BOARD.md).

## Canonical issue body

Parent PRD · User stories · Requirements · **Implementation plan** · **opencode-task-yaml** · Description · Blocked by

Details: [plan-artifact-schema.md](plan-artifact-schema.md).

## Internal scripts (agents only)

Central in `OPENCODE_CONFIG_DIR` — invoke via **`opencode-run`** (never copied into app repos):

| Command | Used by |
|---------|---------|
| `opencode-run --cwd <impl> impl issue-expand-bundle` | issue-expand from spec (sibling path) |
| `opencode-run impl issue-expand-bundle` | issue-expand from impl (deprecated) |
| `opencode-run impl feature-check` | issue-expand (single impl repo) |
| `opencode-run spec feature-check` | feature-upgrade, fanout-issues, issue-expand (all repos) |
| `opencode-run impl orchestrate-readiness-check` | issue-expand, orchestrate bootstrap |
| `opencode-run impl feature-context` | issue-expand, orchestrate |
| `opencode-run spec fanout` | fanout-issues (spec) |
| `resolve_impl_path.sh` | issue-expand (spec → sibling abs path) |

## See also

- [RUNBOOK.md](RUNBOOK.md)
- [skills/orchestrate/SKILL.md](../skills/orchestrate/SKILL.md)
- [skills/ticket-lifecycle/SKILL.md](../skills/ticket-lifecycle/SKILL.md)
- [skills/architect-feature-signoff/SKILL.md](../skills/architect-feature-signoff/SKILL.md)
- [skills/issue-expand/SKILL.md](../skills/issue-expand/SKILL.md)
- [skills/setup-project/SKILL.md](../skills/setup-project/SKILL.md)
- [adr/0006-close-at-merge-and-phase-r.md](adr/0006-close-at-merge-and-phase-r.md)
