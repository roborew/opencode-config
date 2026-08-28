# Feature pipeline

Spec-driven path from PRD to merge. You choose only **architect** or **orchestrate**; open the right repo; for architect start with **`hi`** and pick the menu line shown. Shell bootstrap once (`setup-project`); after that, use OpenCode menus.

User overview (diagram + how-to): [../README.md#feature-flow-prd--sign-off](../README.md#feature-flow-prd--sign-off).

## Flow (what you do)

| Stage | Repo | Select | Your choice | Your job | This stage owns |
|-------|------|--------|-------------|----------|-----------------|
| Plan / PRD | **spec** (`*-spec`) | **architect** → `hi` | **1. Product feature / PRD — …** | Answer grill; **approve** `docs/prd/<slug>.md`; **approve** issue plans | Planning + per-work-repo handoffs only — not code, not PR polish |
| Build | **each work repo** | **orchestrate** (new session) | Paste handoff / `feature:<slug>` | Wait until the feature PR exists | Implements the queue; opens/updates the feature PR |
| Review / accept / docs | **same work repo** | **architect** (new session) → `hi` | **4. Review / sign-off — Mode F …** then **R.** / **1.** / **2.** | Drive review; when happy: **Phase 1** (`state:done`, tickets stay open) then **Phase 2** docs | **All PR readiness and ticket acceptance.** Work-repo architect is where you sign off the work before spec |
| Remediation loop | **same work repo** | **orchestrate** ↔ **architect** | After **R**, if changes needed: **orchestrate** again → then architect → **4** → **R** again | Stay in the work repo until you are happy | Loop until Merge-ready — **do not go to spec yet** |
| Final close | **spec** | **architect** → `hi` | **3. Feature complete — …** | Only after **every** work repo finished Mode F; choose human vs agent **merge gate** | **Merge + close only:** close tickets already `state:done`, merge PRs, close PRD. Spec does **not** re-do review or PR prep |

Shape:

```text
SPEC (start)          WORK REPO (loop until happy)              SPEC (finish)
architect / 1    →    orchestrate ⇄ architect / 4 (R→1→2)   →   architect / 3
PRD + handoffs        build → review → (fix → review)*          merge + close
```

### Hard reminders

- Sign-off of the **work** (review, remediation, `state:done`, docs, PR merge-ready) = **architect in the work repo**.
- Sign-off of the **feature across the stack** (merge + close) = **architect in spec**, menu **3. Feature complete**.
- Spec merge closes **done-state** tickets; getting them to done and getting the PR ready is **work-repo** work.
- Do **not** run Mode F Phase R/1/2 in the spec repo for normal delivery (spec menu **4** is rare cross-repo assist only).

### Session boundaries (recommended)

- **Planning:** `cd` into **spec** → **architect** → `hi` → **1. Product feature / PRD …** (one session through handoffs). Example: `cd ~/code/myapp/myapp-spec`.
- **Build:** `cd` into each **work repo** → **new** session → **orchestrate** → paste `feature:<slug>` (parallel OK when handoff says so). Example: `cd ~/code/myapp/myapp-web`.
- **Review loop (stay in work repo):** **new** session → **architect** → `hi` → **4. Review / sign-off — Mode F …** → **R. Phase R …**. If changes needed → **orchestrate** again → back to architect **4** → **R**. When happy → **1. Phase 1 …** then **2. Phase 2 …**.
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

Skill detail: [skills/architect-review/SKILL.md](../skills/architect-review/SKILL.md).

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
- [skills/issue-expand/SKILL.md](../skills/issue-expand/SKILL.md)
- [skills/setup-project/SKILL.md](../skills/setup-project/SKILL.md)
- [adr/0006-close-at-merge-and-phase-r.md](adr/0006-close-at-merge-and-phase-r.md)
