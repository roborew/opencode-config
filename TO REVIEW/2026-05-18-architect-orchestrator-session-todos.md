# 2026-05-18 — Architect / Orchestrator Session Progress Todos

**Filename date:** `2026-05-18` matches the **Cursor chat creation date** (not the date this `TO REVIEW` file was last edited).

**Session scope:** Fix sticky, intermittent todo-list behaviour between **architect** (planning) and **orchestrate** (execution). Agents were completing real work (including **scribe** `.plan` writes) but often left the host session todo list out of sync—especially the final **scribe** step before handoff—and **orchestrate** sometimes started the stage loop without creating todos from the plan’s **StagePlan**.

**Status:** Designed, implemented, and finalized in the Cursor chat below. Patches were applied in that chat via `StrReplace`; **re-apply** if `rg 'Session progress todos' ~/.config/opencode` returns no matches.

---

## Cursor chat provenance

| Field | Value |
| --- | --- |
| **Chat UUID** | `65446896-4aa6-4b86-af61-51b166ccdfbc` |
| **Transcript path** | `/Users/robo/.cursor/projects/Users-robo-config-opencode/agent-transcripts/65446896-4aa6-4b86-af61-51b166ccdfbc/65446896-4aa6-4b86-af61-51b166ccdfbc.jsonl` |
| **Chat created** | **2026-05-18 12:51 BST** (filesystem birth time on transcript) |
| **Transcript last modified** | 2026-06-01 19:22 BST (follow-up messages: TO REVIEW doc, rename, this expansion) |
| **Config repo** | `/Users/robo/.config/opencode` |
| **Implementation turns** | Transcript lines 9–10 (`StrReplace` on five agent/skill files) |
| **Doc / follow-up turns** | Transcript lines 16+ (TO REVIEW write, rename, detail pass) |

**Naming rule:** `TO REVIEW/YYYY-MM-DD-<slug>.md` uses **`YYYY-MM-DD` = Cursor chat created date** so multiple review docs sort chronologically when you add more sessions.

---

## Original user request (verbatim)

```text
I am finding the todo list handling a bit sticky between architect and orchestrator.  I.e the architect creates a todo list of tasks,  it wokks through them but even though it completes all steps it has not check of the scribe final .plan artifact. It seems to forget to update the todo list. Then when i switch to orchestrator, once the architect has complete. The orchestrator is not generating and trackin tis own todo list. It just gets on with the plan it should read the  plan and generate the todo list. At the mooment both are working intermitantly and should use opencodes todo list system
```

---

## Executive summary

| Area | Outcome |
| --- | --- |
| Root cause | No config text tied the **host session todo** tool to **scribe**, **archive_plan**, or **StagePlan** stages |
| Architect | Mandatory **Session progress todos** + Hard Rule: scribe-before-handoff |
| Orchestrate | Mandatory todos derived from artifact **after path is known**; sync after each verifier-approved stage |
| Skills | `architect-plan`, `orchestrate-execution`, `architect-review` reinforce the same gates |
| Host tool | Uses whatever todo API the host exposes (`merge: true` updates)—not a separate `opencode.json` key |

There is **no** dedicated todo flag in `opencode.json`. Behaviour is enforced by agent/skill markdown so models call the host’s todo tool (Cursor `TodoWrite`, or OpenCode equivalent when exposed).

---

## Problem reported (operator)

1. **Architect** builds a todo list, works through steps, completes work including specialists—but often **does not check off** the final **scribe** `.plan` artifact step, then prompts handoff to orchestrate.
2. **Orchestrate**, after switching from architect, **does not reliably create** its own todo list from the plan; it **jumps into execution** instead of reading **StagePlan** and tracking stages in the session todo UI.
3. Both agents should use the **same session todo system** the host provides, not ad-hoc mental checklists in chat only.

---

## Design principles (final)

1. **Todos mirror protocol gates**, not generic “thinking” items.
2. **Update after every Task** (or equivalent subagent completion): mark the matching item **completed** with **`merge: true`** before the next Task or user-facing “done” message.
3. **Architect Mode A:** Item **Persist plan via `scribe` (primary `.plan`)** must be **completed** before **“Switch to `orchestrate`”**.
4. **Architect Mode B:** Separate todos for **`review` → `document` → each `scribe` doc write → `archive_plan`**; do not end the turn with **archive** still pending.
5. **Orchestrate:** After `.plan` path is fixed, todos include **plan precondition / check-plan** (when that section exists), **one row per stage (+ verifier)**, **Difficulty completion gates**, **QA scribe** (when used), **architect handoff**—created **before** stage 1.
6. **GitHub backlog path** (when enabled): todos mirror **discover → implement → verify → transition → repeat** per issue.

---

## Files changed in chat (nine StrReplace operations)

| # | File | What changed |
| --- | --- | --- |
| 1 | `agents/architect.md` | Insert **Session progress todos** after Agent Identity Guard bullet |
| 2 | `agents/orchestrate.md` | Insert **Session progress todos** after Agent Identity Guard bullet |
| 3 | `skills/architect-plan/SKILL.md` | **Session todos** blurb under Feature Decomposition Protocol |
| 4 | `skills/architect-plan/SKILL.md` | Step 5 scribe + non-feature plan types todo completion |
| 5 | `skills/orchestrate-execution/SKILL.md` | **Session todos** under Plan precondition |
| 6 | `skills/orchestrate-execution/SKILL.md` | Mark check-plan todo before stage 1 |
| 7 | `skills/architect-review/SKILL.md` | Mode B session todos + archive gate |
| 8 | `agents/architect.md` | Hard Rule **14** Session todos |
| 9 | `agents/orchestrate.md` | Hard Rule **10** Session todos |

No changes to `opencode.json`, `agents/scribe.md`, or subagent `permission` blocks.

---

## Host todo tool — patterns for another AI

When the host exposes a todo tool (e.g. Cursor **`TodoWrite`**), agents should:

### 1. Create the list up front (`merge: false`)

**Architect Mode A** (example feature `auth-flow`):

```json
{
  "merge": false,
  "todos": [
    { "id": "ctx-gate", "content": "Claude Context readiness gate", "status": "pending" },
    { "id": "investigate", "content": "Investigate codebase (claude-context)", "status": "pending" },
    { "id": "draft-plan", "content": "Author or merge feature plan sections", "status": "pending" },
    { "id": "scribe-plan", "content": "Persist plan via scribe (.plan/feature.auth-flow.md + tool evidence)", "status": "pending" },
    { "id": "handoff", "content": "Prompt user: Switch to orchestrate", "status": "pending" }
  ]
}
```

**Orchestrate** after reading `.plan/feature.auth-flow.md` with stages `s1`, `s2`, `s3`:

```json
{
  "merge": false,
  "todos": [
    { "id": "check-plan", "content": "check-plan.sh via developer (precondition)", "status": "pending" },
    { "id": "stage-s1", "content": "Stage s1: implement + verifier APPROVED", "status": "pending" },
    { "id": "stage-s2", "content": "Stage s2: implement + verifier APPROVED", "status": "pending" },
    { "id": "stage-s3", "content": "Stage s3: implement + verifier APPROVED", "status": "pending" },
    { "id": "gate-review", "content": "Difficulty gate: review (medium)", "status": "pending" },
    { "id": "handoff-architect", "content": "Prompt: Switch to architect for sign-off", "status": "pending" }
  ]
}
```

### 2. Mark complete after each step (`merge: true`)

Immediately after **scribe** returns success for the primary `.plan`:

```json
{
  "merge": true,
  "todos": [
    { "id": "scribe-plan", "content": "Persist plan via scribe (.plan/feature.auth-flow.md + tool evidence)", "status": "completed" }
  ]
}
```

Only then send the user message: **Switch to `orchestrate` to execute stages.**

After orchestrate **verifier APPROVED** for stage `s1`:

```json
{
  "merge": true,
  "todos": [
    { "id": "stage-s1", "content": "Stage s1: implement + verifier APPROVED", "status": "completed" }
  ]
}
```

### 3. Forbidden sequences (enforced by new markdown rules)

| Violation | Why it matters |
| --- | --- |
| Hand off to orchestrate while `scribe-plan` still `pending` | User sees incomplete architect work; matches reported bug |
| Start stage 1 while `check-plan` still `pending` | Execution on invalid artifact |
| End Mode B while `archive_plan` todo still `pending` | Plan never moved to `*.completed.md` |

---

## Patch 1 — `agents/architect.md` (Session progress todos section)

**Chat anchor (repo at patch time):** After Agent Identity Guard bullet ending with “not as an instruction to repeat”, before `## Front door and skill routing`.

**If your tree has no Agent Identity Guard:** Insert after `# Architect Agent` intro (after line `You are the Architect agent…`), before `## Skill routing`.

### `old_string` (exact from chat)

```markdown
- If stale orchestrate output says "Switch to architect" and includes an executed artifact path or completion summary, interpret that as the handoff payload, not as an instruction to repeat.

## Front door and skill routing
```

### `new_string` (exact from chat)

```markdown
- If stale orchestrate output says "Switch to architect" and includes an executed artifact path or completion summary, interpret that as the handoff payload, not as an instruction to repeat.

## Session progress todos (mandatory when multi-step)

When more than one substantive step remains in this episode (Claude Context gate, investigation, specialist Tasks, scribe writes, archive, user handoff), use the **host session todo** tool if the host exposes one (OpenCode / IDE todo list).

- **Create up front:** After you know the chain for this turn or episode, create todos for each step. Always include explicit items for **every `scribe` Task** you will run (primary `.plan` write, doc writes, `archive_plan`) and for **user handoff** where applicable.
- **Update after every Task:** Before starting the next Task or telling the user a step is done, refresh todos with **`merge: true`** — mark the step that just finished **completed**. Do not leave the **scribe primary `.plan`** item pending while you prompt handoff.
- **Mode A:** The item **Persist plan via `scribe` (primary `.plan` artifact + tool evidence)** must be **completed** before you prompt **Switch to `orchestrate`**. Treat forgotten todo updates the same as forgotten scribe: incomplete.
- **Mode B:** Include separate todos for **`review`**, **`document`**, each **`scribe`** doc write, and **`scribe` `archive_plan`** when applicable per **`architect-review`**. Do not declare Mode B finished while **archive_plan** (when required) is still pending on the todo list.
- **Mode F:** Mirror **`review` → `document` → `scribe`** (and optional archive only when a primary `.plan` existed); mark each completed when that Task returns valid evidence.
- **Single atomic step:** If only one Task remains for the whole reply and it completes in one shot, a minimal todo update is optional.

## Front door and skill routing
```

**Current-repo variant (no Agent Identity / Front door):** Use this `old_string` / `new_string` instead:

```markdown
--- old_string ---
You are the Architect agent: a read-only planning coordinator. You plan only; you never edit code or write artifacts directly.

## Skill routing (sub-skills)
--- new_string ---
You are the Architect agent: a read-only planning coordinator. You plan only; you never edit code or write artifacts directly.

## Session progress todos (mandatory when multi-step)

When more than one substantive step remains in this episode (Claude Context gate, investigation, specialist Tasks, scribe writes, archive, user handoff), use the **host session todo** tool if the host exposes one (OpenCode / IDE todo list).

- **Create up front:** After you know the chain for this turn or episode, create todos for each step. Always include explicit items for **every `scribe` Task** you will run (primary `.plan` write, doc writes, `archive_plan`) and for **user handoff** where applicable.
- **Update after every Task:** Before starting the next Task or telling the user a step is done, refresh todos with **`merge: true`** — mark the step that just finished **completed**. Do not leave the **scribe primary `.plan`** item pending while you prompt handoff.
- **Mode A:** The item **Persist plan via `scribe` (primary `.plan` artifact + tool evidence)** must be **completed** before you prompt **Switch to `orchestrate`**. Treat forgotten todo updates the same as forgotten scribe: incomplete.
- **Mode B:** Include separate todos for **`review`**, **`document`**, each **`scribe`** doc write, and **`scribe` `archive_plan`** per **`architect-review`**. Do not declare Mode B finished while **archive_plan** is still pending on the todo list.
- **Single atomic step:** If only one Task remains for the whole reply and it completes in one shot, a minimal todo update is optional.

## Skill routing (sub-skills)
```

*(Drop **Mode F** bullet if your `architect-review` skill has no Mode F.)*

---

## Patch 2 — `agents/orchestrate.md` (Session progress todos section)

**Chat anchor:** After Agent Identity Guard bullet, before `## Skill routing (sub-skills)`.

**Current-repo anchor:** After orchestrate intro paragraph, before `## Skill routing (sub-skills)`.

### `old_string` (exact from chat)

```markdown
- If stale architect output says "Switch to orchestrate" and includes a review artifact path, interpret that as the handoff payload, not as an instruction to repeat.

## Skill routing (sub-skills)
```

### `new_string` (exact from chat)

```markdown
- If stale architect output says "Switch to orchestrate" and includes a review artifact path, interpret that as the handoff payload, not as an instruction to repeat.

## Session progress todos (mandatory when multi-step)

When a `.plan` artifact path is known (user choice, handoff, or bootstrap selection), use the **host session todo** tool if the host exposes one (OpenCode / IDE todo list).

- **After you have the artifact path:** Read enough of the plan to list **StagePlan** stages (stage ids) and any **Difficulty** completion gates. **Create** todos before the first `developer` precondition or stage Task — typical items: **`check-plan.sh` via `developer`**, **one todo per stage** (implement + verifier pass), **Difficulty gates** (`review` / `senior-dev` / `helper` when required), **QA scribe** (`.qa/<slug>.md` when orchestration completes), **handoff prompt to architect**.
- **GitHub backlog mode:** Create todos for **next-runnable-issue → implement → verify → transition → repeat** so queue progress stays visible.
- **Update after each gate:** After verifier **APPROVED**, after each difficulty gate, and after recovery amends, **`merge: true`** and mark the corresponding todo **completed** before advancing or summarizing.
- **Forbidden:** Starting stage 1 (or reporting "stage N complete") while the todo row for **plan precondition** or that stage is still unchecked if you are using todos this session.
- **Fresh switch from architect:** Even if the chat already summarized the plan, **still** derive todos from the **file** (read StagePlan) in this session — do not skip todo creation because the plan was "described" earlier.

## Skill routing (sub-skills)
```

### Current-repo variant (no Agent Identity Guard)

```markdown
--- old_string ---
You are the Orchestrate agent: a non-writing execution coordinator. You execute plan artifacts by delegating to subagents. You never write or edit files directly.

## Skill routing (sub-skills)
--- new_string ---
You are the Orchestrate agent: a non-writing execution coordinator. You execute plan artifacts by delegating to subagents. You never write or edit files directly.

## Session progress todos (mandatory when multi-step)

When a `.plan` artifact path is known (user choice, handoff, or bootstrap selection), use the **host session todo** tool if the host exposes one (OpenCode / IDE todo list).

- **After you have the artifact path:** Read enough of the plan to list **StagePlan** stages (stage ids) and any **Difficulty** completion gates. **Create** todos before the first stage Task — typical items: **one todo per stage** (implement + verifier pass), **Difficulty gates** (`review` / `senior-dev` / `helper` when required), **handoff prompt to architect**.
- **Update after each gate:** After verifier **APPROVED**, after each difficulty gate, and after recovery amends, **`merge: true`** and mark the corresponding todo **completed** before advancing or summarizing.
- **Forbidden:** Starting stage 1 (or reporting "stage N complete") while that stage’s todo is still unchecked if you are using todos this session.
- **Fresh switch from architect:** Even if the chat already summarized the plan, **still** derive todos from the **file** (read StagePlan) in this session — do not skip todo creation because the plan was "described" earlier.

## Skill routing (sub-skills)
```

---

## Patch 3 — `skills/architect-plan/SKILL.md` (Feature Decomposition Protocol)

### `old_string`

```markdown
## Feature Decomposition Protocol (mandatory for Feature / option 1)

When the user selects Feature, follow this protocol. You **must not** send one huge unscoped prompt to a single strategist when **multiple sub-problems** require strategists; use scoped strategists per sub-problem. **Easy** and **medium single-domain** features skip strategists when you synthesize the plan yourself (see below).

```

### `new_string`

```markdown
## Feature Decomposition Protocol (mandatory for Feature / option 1)

When the user selects Feature, follow this protocol. You **must not** send one huge unscoped prompt to a single strategist when **multiple sub-problems** require strategists; use scoped strategists per sub-problem. **Easy** and **medium single-domain** features skip strategists when you synthesize the plan yourself (see below).

**Session todos:** If the host provides a todo tool, create todos for Steps 0–5 (investigation, strategist wave(s), merge/red-team, **Step 5 scribe + handoff**) and mark each **completed** immediately after that work finishes. The **scribe** item must be **completed** before the "Switch to `orchestrate`" prompt (see architect agent **Session progress todos**).

```

---

## Patch 4 — `skills/architect-plan/SKILL.md` (Step 5)

### `old_string`

```markdown
### Step 5: Scribe and handoff

Pass the feature plan to `scribe` via Task. After scribe success with tool evidence and no `SCRIBE_FAILED`, trust the write (see agent Hard Rules; design artifacts still need content drift check). Prompt user to switch to `orchestrate`.

```

### `new_string`

```markdown
### Step 5: Scribe and handoff

Pass the feature plan to `scribe` via Task. After scribe success with tool evidence and no `SCRIBE_FAILED`, trust the write (see agent Hard Rules; design artifacts still need content drift check). **Mark the session todo for this scribe write completed**, then prompt user to switch to `orchestrate`.

**Other plan types** (debug/refactor/review/design): same rule — todo item for **`scribe` primary artifact** must flip to **completed** before handoff.

```

---

## Patch 5 — `skills/orchestrate-execution/SKILL.md` (Plan precondition)

**Note:** Some repo revisions **removed** `## Plan precondition`; if missing, use **Patch 5b** below instead.

### `old_string`

```markdown
## Plan precondition (mandatory before the stage loop)

When an artifact path is known (user supplied, handoff, or selected from `.plan/`):

1. Invoke **`developer`** via Task with **`load: minimal`** to run this from the **repository root**:

```

### `new_string`

```markdown
## Plan precondition (mandatory before the stage loop)

When an artifact path is known (user supplied, handoff, or selected from `.plan/`):

**Session todos:** If the host provides a todo tool, ensure todos exist for **this precondition**, **each StagePlan stage + verifier**, **Difficulty completion gates**, **final QA scribe**, and **architect handoff** — then keep them in sync after each step (see orchestrate agent **Session progress todos**).

1. Invoke **`developer`** via Task with **`load: minimal`** to run this from the **repository root**:

```

### Patch 5b — current repo (insert before `## Stage Loop`)

If `Plan precondition` is absent, insert immediately before `## Stage Loop`:

```markdown
## Stage execution todos (mandatory when multi-step)

When an artifact path is known, **Session todos:** If the host provides a todo tool, ensure todos exist for **each StagePlan stage + verifier**, **Difficulty completion gates**, and **architect handoff** — then keep them in sync after each step (see orchestrate agent **Session progress todos**).

```

---

## Patch 6 — `skills/orchestrate-execution/SKILL.md` (after check-plan success)

### `old_string`

```markdown
3. On success, continue to **Stage Loop**.

## Session Bootstrap (mandatory, first in fresh context)
```

### `new_string`

```markdown
3. On success, continue to **Stage Loop**. Mark the **check-plan** todo **completed** before starting stage 1.

## Session Bootstrap (mandatory, first in fresh context)
```

**If Plan precondition / step 3 is absent:** Add to the first bullet under `## Stage Loop`: “Before dispatching stage 1, mark any **plan-read / precondition** todo **completed**.”

---

## Patch 7 — `skills/architect-review/SKILL.md` (Mode B)

### `old_string`

```markdown
## Mode B — Post-implementation (review + documentation)

When user reports orchestrate has completed implementation and verifier passed, you run **review**, then **documentation**, then **mandatory plan archive** on sign-off. Invoke `review` for final sign-off; if sign-off, invoke `document` for doc content, then `scribe` to write docs, then **`scribe` again for `archive_plan`** (see step 6). **Mode B is not finished until the plan file is renamed to `*.completed.md` or scribe reports `SCRIBE_FAILED` on archive after retry.**

```

### `new_string`

```markdown
## Mode B — Post-implementation (review + documentation)

When user reports orchestrate has completed implementation and verifier passed, you run **review**, then **documentation**, then **mandatory plan archive** on sign-off. Invoke `review` for final sign-off; if sign-off, invoke `document` for doc content, then `scribe` to write docs, then **`scribe` again for `archive_plan`** (see step 6). **Mode B is not finished until the plan file is renamed to `*.completed.md` or scribe reports `SCRIBE_FAILED` on archive after retry.**

**Session todos:** If the host provides a todo tool, create items for **`review` → `document` → each `scribe` write → `archive_plan` (when required)** and mark each **completed** as soon as that Task returns valid evidence. Do not end the turn with **`archive_plan`** still showing pending.

```

---

## Patch 8 — `agents/architect.md` (Hard Rule)

**Chat:** Added rule **14** after rule 13 Pre-planning interview.

**Current repo:** Rules end at **12**; append as **13** (or renumber Mode B archive rule if you prefer todos adjacent to archive gate).

### `old_string` (chat)

```markdown
13. **Pre-planning interview.** In Mode A, after the user picks a plan type and gives their first substantive requirements description, complete **`grill-me`** per **Skill routing** before starting planning discovery, **Difficulty**, strategist/specialist work, or scribe for that artifact.

## After Planning
```

### `new_string` (chat)

```markdown
13. **Pre-planning interview.** In Mode A, after the user picks a plan type and gives their first substantive requirements description, complete **`grill-me`** per **Skill routing** before starting planning discovery, **Difficulty**, strategist/specialist work, or scribe for that artifact.
14. **Session todos.** Follow **Session progress todos** above whenever you use the host todo tool: never hand off to `orchestrate` while the **scribe primary `.plan`** step is still unchecked.

## After Planning
```

### Current-repo `old_string` / `new_string`

```markdown
--- old_string ---
12. **Pre-planning interview.** In Mode A, after the user picks a plan type and gives their first substantive requirements description, complete **`grill-me`** per **Skill routing** before starting planning discovery, **Difficulty**, strategist/specialist work, or scribe for that artifact.

## After Planning
--- new_string ---
12. **Pre-planning interview.** In Mode A, after the user picks a plan type and gives their first substantive requirements description, complete **`grill-me`** per **Skill routing** before starting planning discovery, **Difficulty**, strategist/specialist work, or scribe for that artifact.
13. **Session todos.** Follow **Session progress todos** above whenever you use the host todo tool: never hand off to `orchestrate` while the **scribe primary `.plan`** step is still unchecked.

## After Planning
```

---

## Patch 9 — `agents/orchestrate.md` (Hard Rule)

**Chat:** Added rule **10** after Brevity rule 9.

**Current repo:** Brevity is rule **8**; append as **9**.

### `old_string` (chat)

```markdown
9. **Brevity.** Default to concise structured output: short headings + bullet lists. **Do not narrate reasoning** unless the user **explicitly** asks. **Never repeat** unchanged artifact sections; if something changed, state the **delta** only.

## Safety Hard Rules (do not delegate unsafe work)
```

### `new_string` (chat)

```markdown
9. **Brevity.** Default to concise structured output: short headings + bullet lists. **Do not narrate reasoning** unless the user **explicitly** asks. **Never repeat** unchanged artifact sections; if something changed, state the **delta** only.
10. **Session todos.** Follow **Session progress todos** above when using the host todo tool: after a `.plan` path is fixed, mirror **StagePlan** + gates in todos and sync after each verifier-approved stage.

## Safety Hard Rules (do not delegate unsafe work)
```

### Current-repo `old_string` / `new_string`

```markdown
--- old_string ---
8. **Brevity.** Default to concise structured output: short headings + bullet lists. **Do not narrate reasoning** unless the user **explicitly** asks. **Never repeat** unchanged artifact sections; if something changed, state the **delta** only.

## Safety Hard Rules (do not delegate unsafe work)
--- new_string ---
8. **Brevity.** Default to concise structured output: short headings + bullet lists. **Do not narrate reasoning** unless the user **explicitly** asks. **Never repeat** unchanged artifact sections; if something changed, state the **delta** only.
9. **Session todos.** Follow **Session progress todos** above when using the host todo tool: after a `.plan` path is fixed, mirror **StagePlan** + gates in todos and sync after each verifier-approved stage.

## Safety Hard Rules (do not delegate unsafe work)
```

---

## Expected operator behaviour (after re-apply)

| Phase | Todo list should show |
| --- | --- |
| Architect planning | Investigation → strategists (if any) → merge → **scribe `.plan`** → handoff prompt |
| Architect Mode B | **review** → **document** → doc **scribe** writes → **archive_plan** |
| Orchestrate start | **check-plan** (if used) → **stage-1 … stage-N** → difficulty gates → architect prompt |
| During orchestrate | Current stage in progress; prior stages **completed** on list |

---

## Verification checklist

```bash
cd ~/.config/opencode
rg -l 'Session progress todos|host session todo' agents skills
```

Expect **five** paths when fully applied:

- `agents/architect.md`
- `agents/orchestrate.md`
- `skills/architect-plan/SKILL.md`
- `skills/orchestrate-execution/SKILL.md`
- `skills/architect-review/SKILL.md`

**Manual smoke:**

1. Architect: plan a small feature → **scribe** todo completes before orchestrate handoff.
2. Orchestrate: select `.plan` → todos appear **before** stage 1; each stage todo completes after verifier **APPROVED**.
3. Architect Mode B: **archive_plan** todo completes before “review cycle finished”.

---

## Related protocol (unchanged by this chat — context for todos)

These existing rules are what todos must stay aligned with:

**Architect — scribe handoff (Hard Rule 5):**

```markdown
5. **User handoff.** After scribe confirms a successful write (per rule 4), explicitly prompt: "Switch to `orchestrate` to execute stages." Do not invoke orchestrate yourself.
```

**Architect — Mode B archive (Hard Rule 10 in current repo):**

```markdown
10. **Mode B archive gate.** After review sign-off, after `document` and any doc scribe writes (including zero docs), you **must** Task `scribe` with `operation: archive_plan` and explicit `source_path` / `target_path` per **`architect-review`**. Do not skip this Task. Do not claim Mode B is complete without archive success or documented `SCRIBE_FAILED` after retry.
```

**Orchestrate — one stage at a time (Hard Rule 4):**

```markdown
4. Execute one stage at a time; require completion report before next stage.
```

---

## Out of scope (this chat)

- Enabling or configuring a todo tool in `opencode.json` (host-dependent).
- Changes to **scribe**, **developer**, or **verifier** agent files.
- Commits or PR creation.

---

## Re-application procedure (for another AI)

1. Confirm chat date: transcript birth **2026-05-18** → filename `2026-05-18-architect-orchestrator-session-todos.md`.
2. Run verification `rg` above; if empty, apply patches **1–9** in order.
3. Prefer **current-repo variant** anchors when Agent Identity Guard / Plan precondition / rule numbers differ.
4. Re-run `rg` and manual smoke tests.
5. Do not change unrelated agent prose (brevity, grill-me routing, etc.).

---

## Document history

| Date | Event |
| --- | --- |
| 2026-05-18 12:51 | Cursor chat created; todo implementation patches (transcript lines 9–10) |
| 2026-06-01 | TO REVIEW doc first written; renamed to `2026-05-18-*`; expanded with full patches and chat provenance |
