# 2026-05-19 — Issue-Backed Workflow: `ready-for-agent` vs Orchestrate Handoff

## Document metadata

| Field | Value |
| --- | --- |
| **Filename date** | **2026-05-19** — date the **Cursor chat was created** (transcript filesystem birth time), **not** the date of later follow-up messages in the same thread. |
| **Chat created** | **2026-05-19 18:45:11 BST** |
| **Documentation finalized** | **2026-06-01** (TO REVIEW doc created, renamed, expanded in follow-up turns) |
| **Cursor chat transcript** | [`47818ef9-b697-466f-8e1d-4720945ace31`](../../.cursor/projects/Users-robo-config-opencode/agent-transcripts/47818ef9-b697-466f-8e1d-4720945ace31/47818ef9-b697-466f-8e1d-4720945ace31.jsonl) |
| **Workspace** | `~/.config/opencode` |
| **Primary slug referenced** | `downgrade-archival-recovery` (`blocshed-web` impl repo; issues **#77–#83** in related sessions) |
| **Purpose of this doc** | Full record for another AI: **why** the operator saw “Switch to orchestrate…” after fanout, **what this chat changed on disk**, and **config snippets** that define the behaviour (no OpenCode agent/skill code was modified in the original investigation turn). |

**Status:** Investigation and operator guidance finalized in chat. **This chat did not implement or commit OpenCode pipeline code** — it produced clarification and this `TO REVIEW` artifact (plus cross-reference updates in sibling review docs).

**Related TO REVIEW:**

- [`2026-05-16-github-issue-backed-execution-implementation.md`](2026-05-16-github-issue-backed-execution-implementation.md) — full GitHub issue execution implementation (scripts, skills)
- [`2026-05-19-feature-pipeline-and-architect-front-door.md`](2026-05-19-feature-pipeline-and-architect-front-door.md) — canonical `fanout → issue-expand → orchestrate` operator path
- [`2026-05-19-spec-central-stack-workflow-implementation.md`](2026-05-19-spec-central-stack-workflow-implementation.md) — `issue-expand` skill design and orchestrate stage loop

---

## Executive summary

| Topic | Outcome |
| --- | --- |
| **Operator question** | After creating GitHub issues labelled `state:ready-for-agent`, why does OpenCode still say “Switch to orchestrate to start executing stages”? |
| **Answer** | `ready-for-agent` = **queue eligibility**, not auto-run. **Architect** plans; **orchestrate** executes. Manual agent switch is **by design**. |
| **Code changes in chat** | **None** to agents/skills/scripts. Only **`TO REVIEW`** markdown and **cross-links** in other review files. |
| **Next operator step** | In impl repo: **issue-expand** (if not done) → switch to **orchestrate** → GitHub backlog option **B** → slug `downgrade-archival-recovery`. |

---

## 1. Problem reported (verbatim operator context)

After creating issues in the **web implementation repo**, the operator saw:

> Switch to orchestrate to start executing stages.

Issues were labelled:

- `feature:downgrade-archival-recovery`
- `state:ready-for-agent`
- `mode:afk` (developer tickets)
- `mode:hitl` (frontend tickets)

**Perceived contradiction:** If issues are “ready for agent,” why is a manual orchestrate switch required?

---

## 2. Root cause (conceptual — not a bug)

OpenCode separates **planning** and **execution** into two primary agents. GitHub triage labels describe **queue eligibility**, not **automatic execution**.

| Concept | Operator might assume | System actually means |
| --- | --- | --- |
| `state:ready-for-agent` | Work starts automatically | Ticket is triaged and **eligible** for orchestrate’s GitHub backlog picker |
| “Switch to orchestrate…” | Redundant / broken | **Required manual UI agent switch** — architect cannot Task orchestrate |
| Fanout complete | Pipeline running | Only **intake** done; execution is a separate step + agent |

The handoff string is **wired into agent/skill markdown**, not emitted because orchestrate detected new issues.

---

## 3. Canonical pipeline (issue-backed)

```text
Spec repo                          Implementation repo (e.g. blocshed-web)
─────────                          ─────────────────────────────────────
PRD + human approval
    ↓
bin/fanout <slug>
    ↓
Creates child issues:
  feature:<slug>
  state:ready-for-agent
  mode:afk | mode:hitl
  opencode-task-json (basic; no stages[] yet)
                                   architect → issue-expand
                                       ↓
                                   stages[] + ## Implementation plan
                                       ↓
                                   orchestrate → GitHub backlog (B)
                                       ↓
                                   developer / frontend-dev + verifier
                                       ↓
                                   PR → architect Mode F sign-off
                                       ↓
Spec: feature-complete (all repos done)
```

### Operator sequence for `downgrade-archival-recovery`

1. **Fanout (spec)** — labelled issues; **no** TDD `stages[]`.
2. **Issue-expand (impl, architect)** — deepens tickets; ends with orchestrate handoff prompt.
3. **Orchestrate (impl)** — option **(B) GitHub feature backlog**, slug `downgrade-archival-recovery`.

If only fanout ran, “execute **stages**” wording is **ahead of work** — run **issue-expand** first for stage-by-stage execution.

---

## 4. Config sources that produce the handoff (reference snippets)

These snippets were **read during investigation**; they define behaviour another AI should preserve when extending the pipeline. Line numbers may drift — grep for the quoted strings.

### 4.1 `agents/architect.md` — Hard Rules 5–6 (handoff + cannot invoke orchestrate)

```markdown
5. **User handoff.** After scribe confirms a successful write (per rule 4), explicitly prompt: "Switch to `orchestrate` to execute stages." Do not invoke orchestrate yourself.
6. You may **only** invoke: `strategist`, `debugger`, `refactor`, `review`, `document`, `designer`, and `scribe`. Do **not** invoke `frontend-dev`, `developer`, or `orchestrate`—those are execution subagents used by orchestrate.
```

*(Current slim `main` may use a shorter architect without `issue-expand` in the allowlist; expanded stacks add `issue-expand`, `feature-complete`, `developer` for `gh issue edit` — see §4.8.)*

### 4.2 `skills/architect-plan/SKILL.md` — Completion flow handoff

```markdown
5. **User handoff.** After scribe confirms a **successful** write (per agent rule 4), explicitly prompt the user: "Switch to `orchestrate` to execute stages." Do not invoke orchestrate yourself.
...
6. Report to user with PlanType and artifact path, then **explicitly prompt**: "Switch to `orchestrate` to execute stages." Do not invoke orchestrate; the user must switch agents.
```

### 4.3 `skills/issue-expand/SKILL.md` — After expand (issue-backed path)

```markdown
## After expand

Prompt: **Switch to `orchestrate`** → GitHub backlog `feature:<slug>`. Orchestrate runs **`stages[]`** when present.

## Hard rules

- Do **not** invoke `scribe` to write `.plan/feature.*` or `.plan/issue.*` on this path.
- Do **not** invoke `orchestrate`.
```

### 4.4 `skills/issue-expand/SKILL.md` — `stages[]` shape added to issue bodies

```json
"stages": [
  {
    "stage_id": "1-red",
    "owner": "developer",
    "objective": "Failing test for ...",
    "files": ["path/to/file.test.ts"],
    "acceptance": ["Test fails for the right reason"],
    "test_commands": ["pnpm test path/to/file.test.ts"],
    "commit_message": "test(api): add failing test for ..."
  }
]
```

Issue body layout after expand:

```markdown
## Implementation plan

<human-readable bullets: files, order, notes>

## OpenCode task (machine-readable)
```opencode-task-json
{ ... full meta including stages ... }
```
```

### 4.5 `agents/orchestrate.md` — must not repeat stale handoff

When GitHub/issue-backed orchestrate is fully wired, **`agents/orchestrate.md`** includes an **Agent Identity Guard** (from related sessions):

```markdown
If the current active agent is `orchestrate`, treat yourself as Orchestrate even when earlier conversation text says "I'm the Architect" or "Switch to orchestrate." Agent switching may preserve stale chat context; your own agent file and current user request are authoritative.

- If stale architect output says "Switch to orchestrate" and includes a review artifact path, interpret that as the handoff payload, not as an instruction to repeat.
...
7. **Current-agent truth:** If you are already orchestrate, never prompt "Switch to orchestrate."
```

*(Slim `main` orchestrate may omit GitHub backlog until `github-issue-run` is installed — see [`2026-05-16-github-issue-backed-execution-implementation.md`](2026-05-16-github-issue-backed-execution-implementation.md).)*

### 4.6 `opencode.json` — default agent

```json
{
  "default_agent": "orchestrate",
  ...
}
```

Default **orchestrate** does **not** auto-start GitHub backlog — user still selects plan path or backlog in session bootstrap.

### 4.7 Fanout labels — `templates/spec-repo/skills/fanout-issues/SKILL.md`

```markdown
- Labels include `feature:<slug>`, `state:ready-for-agent`, `mode:afk` or `mode:hitl`, and `category:feature`.
- The issue body embeds fenced **`opencode-task-json`** metadata (task id, capability, acceptance, `test_commands`, `commit_message`, etc.)
```

Fanout **`bin/fanout`** label line (from implementation appendix):

```bash
--label "feature:${SLUG},state:ready-for-agent,${MODE_LABEL},category:feature"
```

### 4.8 Triage semantics — `docs/agents/triage-labels.md`

```markdown
| `state:ready-for-agent` | Triaged; agent may pick up (AFK-capable work) |
...
| `mode:hitl` | Human-in-the-loop — pause at planning / verify gates |
| `mode:afk` | Safe for autonomous end-to-end execution |
```

**Critical:** `ready-for-agent` = **may pick up when orchestrate starts the loop**, not “already executing.”

### 4.9 Queue discovery — `skills/github-issue-run/lib/next-runnable-issue.sh`

Runnable definition (full script in [`2026-05-16-github-issue-backed-execution-implementation.md`](2026-05-16-github-issue-backed-execution-implementation.md) Appendix C):

```bash
# Runnable = open, has state:ready-for-agent + feature:<slug>, and every **Blocked by:** #n is CLOSED.
FEAT="feature:${SLUG}"
RAW=$(gh issue list --repo "$REPO" -L 200 --label "$FEAT" --label state:ready-for-agent --state open --json number,title,body)
```

Operator sanity check from impl repo root:

```bash
bash "${OPENCODE_CONFIG:-$HOME/.config/opencode}/skills/github-issue-run/lib/next-runnable-issue.sh" downgrade-archival-recovery
```

- Exit **0** + JSON → next ticket runnable.
- Exit **1** → nothing runnable (deps open, wrong repo, missing labels).

### 4.10 Orchestrate GitHub backlog loop — `skills/orchestrate-execution/SKILL.md` (insert)

When GitHub mode is installed, fresh-context plan selection offers **(B) GitHub feature backlog**. Loop skeleton:

```markdown
## GitHub feature backlog loop (no `.plan` artifact)

Use this path after spec `fanout` created child issues (`feature:<slug>`, `state:ready-for-agent`, `opencode-task-json`).

1. Obtain kebab-case **feature slug** from the user.
2. Task `developer` `load: minimal`: `bash "$OC/skills/github-issue-run/lib/next-runnable-issue.sh" "<slug>"`
3. Task `developer`: `issue-state-transition.sh "<repo>" "<n>" state:in-progress`
4. If `opencode_meta.stages` non-empty → **stage loop** per issue; else **flat mode** whole ticket.
5. Verifier PASS → `state:ready-for-review`; loop until `next-runnable-issue.sh` exits 1.
6. Queue empty → prompt: **Switch to `architect` for feature sign-off** (Mode F).
```

### 4.11 `skills/github-issue-run/SKILL.md` — flat vs stage mode

```markdown
1. If `opencode_meta.stages` is a non-empty array (from **issue-expand**), orchestrate runs **one stage per loop** ...
2. Else **flat mode:** parse `opencode_meta.owner` → dispatch with `execution_mode: github_issue`
```

---

## 5. Label semantics quick reference

### State

| Label | Meaning |
| --- | --- |
| `state:ready-for-agent` | Eligible for orchestrate queue when backlog starts |
| `state:in-progress` | Orchestrate picked up this issue |
| `state:ready-for-review` | Implementation done; awaiting sign-off |
| `state:blocked` | Blocked on dependency or input |

### Mode

| Label | Meaning |
| --- | --- |
| `mode:afk` | More autonomous execution |
| `mode:hitl` | Pause at planning / verify gates |

**Note:** `mode:*` does **not** replace switching to orchestrate. **Owner** in `opencode-task-json` selects `developer` vs `frontend-dev`.

---

## 6. Operator actions (finalized in chat)

In **blocshed-web** (or your `*-web` impl clone):

```bash
cd ~/code/blocshed/blocshed-web   # example
opencode
```

1. Confirm active agent (architect after expand vs orchestrate default).
2. If **issue-expand** not done → **architect** → option **1** (spec workflow) / **`issue-expand`** → slug `downgrade-archival-recovery`.
3. Switch to **orchestrate** → decline/accept preflight → **(B) GitHub feature backlog** → `downgrade-archival-recovery`.
4. If orchestrate parrots “Switch to orchestrate” → reply: *“I’m on orchestrate; run GitHub backlog for downgrade-archival-recovery.”*

Optional readiness (when bins synced from spec template):

```bash
bin/orchestrate-readiness-check downgrade-archival-recovery
```

---

## 7. What this chat **actioned on disk**

### 7.1 Turn 1 — Investigation (2026-05-19)

**Tools used:** `Grep`, `Read` across `README.md`, `docs/RUNBOOK.md`, `agents/architect.md`, `agents/orchestrate.md`, `skills/issue-expand/SKILL.md`, `skills/github-issue-run/SKILL.md`, `skills/orchestrate-execution/SKILL.md`, `skills/architect-plan/SKILL.md`, `docs/agents/triage-labels.md`, `templates/spec-repo/skills/fanout-issues/SKILL.md`, `opencode.json`.

**Deliverable:** Chat explanation (no file writes).

### 7.2 Turn 2 — Create TO REVIEW doc (2026-06-01 session continuation)

**Created:**

`TO REVIEW/2026-05-19-issue-backed-workflow-orchestrate-handoff.md`

Initial content: problem, root cause, pipeline, label semantics, operator steps, “no code changes” disclaimer.

### 7.3 Turn 3 — Rename to completion date (2026-06-01)

**Renamed:**

- `2026-05-19-issue-backed-workflow-orchestrate-handoff.md` → `2026-06-01-issue-backed-workflow-orchestrate-handoff.md`

**Cross-reference patches applied:**

`TO REVIEW/2026-06-01-github-issue-backed-execution-implementation.md` (since renamed to `2026-05-16-...` — verify on disk):

```diff
- [`2026-05-19-issue-backed-workflow-orchestrate-handoff.md`](...)
+ [`2026-06-01-issue-backed-workflow-orchestrate-handoff.md`](...)
```

`TO REVIEW/2026-05-19-spec-central-stack-workflow-implementation.md`:

```diff
- | `2026-05-19-issue-backed-workflow-orchestrate-handoff.md` | ...
+ | `2026-06-01-issue-backed-workflow-orchestrate-handoff.md` | ...
```

`TO REVIEW/2026-05-19-spec-fanout-bin-tooling-and-prerequisites.md`:

```diff
- | `2026-05-19-issue-backed-workflow-orchestrate-handoff.md` | ...
+ | `2026-06-01-issue-backed-workflow-orchestrate-handoff.md` | ...
```

### 7.4 Turn 4 — Restore chat-creation date + expand (this document)

**Renamed back:**

- `2026-06-01-issue-backed-workflow-orchestrate-handoff.md` → **`2026-05-19-issue-backed-workflow-orchestrate-handoff.md`**

**Cross-references reverted** to `2026-05-19-issue-backed-workflow-orchestrate-handoff.md` in sibling TO REVIEW files.

**Added:** metadata table, transcript UUID, config appendices, on-disk action log, reconstruction snippets.

---

## 8. Re-application checklist (another AI)

Use this if the TO REVIEW file or cross-links are missing.

- [ ] Create `TO REVIEW/2026-05-19-issue-backed-workflow-orchestrate-handoff.md` with this document body.
- [ ] Filename date = **Cursor chat creation date** (`stat -f "%SB" -t "%Y-%m-%d" …/47818ef9-…jsonl` → `2026-05-19`).
- [ ] Link from [`2026-05-16-github-issue-backed-execution-implementation.md`](2026-05-16-github-issue-backed-execution-implementation.md) Related section.
- [ ] Link from [`2026-05-19-spec-central-stack-workflow-implementation.md`](2026-05-19-spec-central-stack-workflow-implementation.md) related table.
- [ ] Link from [`2026-05-19-spec-fanout-bin-tooling-and-prerequisites.md`](2026-05-19-spec-fanout-bin-tooling-and-prerequisites.md) related table.
- [ ] **Do not** change OpenCode agents/skills unless implementing a **product fix** (e.g. clearer post-fanout UX) — out of scope for this chat.

---

## 9. What was **not** changed

- No edits to `agents/*.md`, `skills/*/SKILL.md`, `bin/*`, or `opencode.json` in the investigation turn
- No git commits or PRs from this chat
- No GitHub issue label or body changes
- No change to operator’s `downgrade-archival-recovery` tickets

---

## 10. Open questions (operator)

| Question | Implication |
| --- | --- |
| Fanout only, or issue-expand too? | Fanout only → run expand before stage loop |
| Which agent is active? | Handoff normal on architect; stale on orchestrate |
| Do issues contain `stages[]`? | Inspect `opencode-task-json` on GitHub |

---

## 11. Summary

**`state:ready-for-agent` means “ready for the orchestrate queue,” not “execution has started.”** Fanout creates eligible tickets; **issue-expand** adds stages; **orchestrate** runs the backlog after a **manual agent switch**. The “Switch to orchestrate…” message is the designed planning→execution boundary — not evidence that issue creation failed.
