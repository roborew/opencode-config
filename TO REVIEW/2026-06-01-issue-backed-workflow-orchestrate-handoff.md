# 2026-06-01 — Issue-Backed Workflow: `ready-for-agent` vs Orchestrate Handoff

**Filename date (`2026-06-01`):** Date this chat **finished** the investigation and documentation work, not the calendar day of the original operator question alone.

**Session scope:** Explain why the operator saw “Switch to orchestrate to start executing stages” after creating GitHub issues in the web implementation repo for feature `downgrade-archival-recovery`, despite issues already being labeled `state:ready-for-agent`, `mode:afk`, and `mode:hitl`.

**Status:** Investigation and operator guidance finalized in chat. **No code changes were implemented or committed in this session.**

---

## Problem reported

After creating issues in the **web implementation repo** (via spec `fanout` or equivalent), the operator saw a prompt to **switch to orchestrate to start executing stages**. The issues were labeled:

- `feature:downgrade-archival-recovery`
- `state:ready-for-agent`
- `mode:afk` (developer tickets)
- `mode:hitl` (frontend tickets)

This felt contradictory: if issues are “ready for agent,” why is a manual agent switch required?

---

## Root cause (conceptual, not a bug)

OpenCode separates **planning** and **execution** into two primary agents. GitHub triage labels describe **queue eligibility**, not **automatic execution**.

| Concept | What the operator might assume | What the system actually means |
|--------|--------------------------------|--------------------------------|
| `state:ready-for-agent` | Work should start automatically | Ticket is triaged and **eligible** for orchestrate’s GitHub backlog picker |
| “Switch to orchestrate…” | Redundant / broken handoff | **Required manual agent switch** — architect cannot invoke orchestrate |
| Issue creation complete | Pipeline is running | Only **fanout / issue creation** is done; execution is a separate step |

The handoff message is **by design**. It comes from architect / `issue-expand` instructions after planning completes, not from orchestrate detecting that issues exist.

---

## Canonical issue-backed pipeline

Documented in `README.md`, `docs/RUNBOOK.md`, and related skills:

```text
Spec repo                          Implementation repo (e.g. web)
─────────                          ─────────────────────────────
PRD + human approval
    ↓
bin/fanout <slug>
    ↓
Creates child issues with:
  feature:<slug>
  state:ready-for-agent
  mode:afk | mode:hitl
  opencode-task-json (basic metadata, no stages[] yet)
                                   architect → issue-expand
                                       ↓
                                   Adds stages[] + Implementation plan
                                   to each issue body
                                       ↓
                                   orchestrate → GitHub backlog (option B)
                                       ↓
                                   developer / frontend-dev + verifier
                                       ↓
                                   PR → architect Mode F sign-off
                                       ↓
Spec: feature-complete (when all repos done)
```

### Step-by-step for `downgrade-archival-recovery`

1. **Fanout (spec repo)** — Creates labeled issues in target impl repos. Does **not** add TDD `stages[]`.
2. **Issue-expand (impl repo, architect agent)** — Deepens each ticket: `## Implementation plan`, `stages` array inside fenced `opencode-task-json`. Ends with handoff: switch to orchestrate.
3. **Orchestrate (impl repo)** — User selects **(B) GitHub feature backlog**, slug `downgrade-archival-recovery`. Picks next runnable issue via `next-runnable-issue.sh`, runs stage loop or flat mode, transitions labels (`state:in-progress` → `state:ready-for-review`, etc.).

---

## Where the handoff message comes from

| Source | Message / behaviour |
|--------|---------------------|
| `agents/architect.md` (Hard Rule 5) | After scribe confirms a `.plan` write: “Switch to `orchestrate` to execute stages.” |
| `skills/issue-expand/SKILL.md` (§ After expand) | “Switch to `orchestrate` → GitHub backlog `feature:<slug>`.” |
| `skills/architect-plan/SKILL.md` | Same handoff after legacy local `.plan` path |
| `agents/orchestrate.md` | If **already** orchestrate: **must not** repeat “Switch to orchestrate”; proceed from handoff context |

Architect **cannot** invoke orchestrate (`agents/architect.md` Hard Rule 6). The user must change agents in the OpenCode UI.

---

## Label semantics (canonical)

From `docs/agents/triage-labels.md`:

### State

| Label | Meaning |
|-------|---------|
| `state:ready-for-agent` | Triaged; agent **may pick up** when orchestrate starts the backlog loop |
| `state:in-progress` | Orchestrate has started work on this issue |
| `state:ready-for-review` | Implementation complete; awaiting sign-off |
| `state:blocked` | Dependency or external input unresolved |

### Mode (execution policy)

| Label | Meaning |
|-------|---------|
| `mode:afk` | Safer for autonomous end-to-end execution |
| `mode:hitl` | Human-in-the-loop — pause at planning / verify gates |

**Note:** `mode:afk` / `mode:hitl` do **not** replace the orchestrate agent switch. They describe how much human gating to expect **during** execution. **Who implements** (`developer` vs `frontend-dev`) comes from `owner` in `opencode-task-json`, not from the mode label alone.

---

## Orchestrate execution modes (GitHub path)

From `skills/github-issue-run/SKILL.md`:

- **Stage mode** — If `opencode_meta.stages` is a non-empty array (added by **issue-expand**), orchestrate runs one stage per loop before advancing to the next issue.
- **Flat mode** — If no `stages[]`, orchestrate dispatches the whole ticket in one pass using `opencode_meta` acceptance + test commands.

If only **fanout** was run and **issue-expand** was skipped, the “execute **stages**” wording in the handoff is **ahead of the work** — expand is the recommended next step before orchestrate.

---

## Operator actions (finalized guidance)

In the **web implementation repo**:

1. **Confirm current agent** — Default in `opencode.json` is `orchestrate`, but the session may still be on **architect** after expand or planning.
2. **If issue-expand not done** — Switch to **architect** → option 2 → **A) Issue-backed** → run **`issue-expand`** for `downgrade-archival-recovery`.
3. **On orchestrate** — Accept or decline startup preflight; choose **(B) GitHub feature backlog**; slug **`downgrade-archival-recovery`**.
4. **If orchestrate only repeats the handoff** — Tell it explicitly: *“I’m on orchestrate; run GitHub backlog for downgrade-archival-recovery.”*

### Queue sanity check (shell)

From the impl repo root:

```bash
bash "${OPENCODE_CONFIG:-$HOME/.config/opencode}/skills/github-issue-run/lib/next-runnable-issue.sh" downgrade-archival-recovery
```

- **Exit 0 + JSON** — Next ticket is runnable; orchestrate can proceed.
- **Exit 1** — Nothing runnable (dependencies open, wrong repo, slug/label mismatch, or no matching issues).

---

## Key files referenced

| Path | Relevance |
|------|-----------|
| `README.md` | Daily use: issue-expand → orchestrate → PR → feature-complete |
| `docs/RUNBOOK.md` | Full pipeline, agent roles, GitHub mode |
| `docs/agents/triage-labels.md` | Canonical label meanings |
| `skills/issue-expand/SKILL.md` | Adds `stages[]`; post-expand orchestrate handoff |
| `skills/github-issue-run/SKILL.md` | Discovery, state transitions, flat vs stage mode |
| `skills/orchestrate-execution/SKILL.md` | GitHub backlog loop (option B), session bootstrap |
| `agents/architect.md` | Handoff rules; cannot invoke orchestrate |
| `agents/orchestrate.md` | Must not repeat handoff when already orchestrate |
| `templates/spec-repo/skills/fanout-issues/SKILL.md` | Labels applied at fanout time |

---

## What was **not** changed in this session

- No edits to agent markdown, skills, scripts, or `opencode.json`
- No commits or PRs
- No changes to triage labels or GitHub issues

This document captures **operator-facing clarification** only.

---

## Open questions / follow-ups (for operator)

| Question | Implication |
|----------|-------------|
| Was only **fanout** run, or also **issue-expand**? | If fanout only → run expand before expecting stage-by-stage execution |
| Which agent is active in the OpenCode session? | Handoff message is normal on architect; stale if already on orchestrate |
| Do issues have `stages[]` in `opencode-task-json`? | Inspect issue bodies on GitHub to confirm expand completed |

---

## Summary

**`state:ready-for-agent` means “ready for the orchestrate queue,” not “execution has started.”** Creating labeled issues completes the **intake** step; **issue-expand** (optional but recommended) adds stages; **orchestrate** (after a manual agent switch) runs the backlog. The “Switch to orchestrate…” message is the designed boundary between planning and execution, not an indication that something failed during issue creation.
