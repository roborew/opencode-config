# 2026-05-18 — Architect / Orchestrator Session Progress Todos

**Session scope:** Fix sticky, intermittent todo-list behaviour between **architect** (planning) and **orchestrate** (execution). Agents were completing real work (including **scribe** `.plan` writes) but often left the host session todo list out of sync—especially the final **scribe** step before handoff—and **orchestrate** sometimes started the stage loop without creating todos from the plan’s **StagePlan**.

**Work completed:** 2026-05-18 (this chat session; transcript `65446896-4aa6-4b86-af61-51b166ccdfbc`). **TO REVIEW doc written:** 2026-06-01.

**Status:** Designed, edited, and finalized in this chat. **Re-apply** the file changes below if `rg 'Session progress todos' ~/.config/opencode` returns no matches (workspace was verified empty at doc write time).

**Naming:** File prefix `2026-05-18-` is the **work-completion date** (ISO `YYYY-MM-DD`, then slug) so `TO REVIEW` sorts in chronological order when you add later sessions.

---

## Executive summary

| Area | Outcome |
| --- | --- |
| Root cause | No config text tied the **host session todo** tool to **scribe**, **archive_plan**, or **StagePlan** stages |
| Architect | Mandatory **Session progress todos** + Hard Rule for scribe-before-handoff |
| Orchestrate | Mandatory todos derived from artifact **after path is known**; sync after each verifier-approved stage |
| Skills | `architect-plan`, `orchestrate-execution`, `architect-review` reinforce the same gates |
| Host tool | Uses whatever todo API the OpenCode / IDE session exposes (`merge: true` updates)—not a separate OpenCode config key |

---

## Problem reported (operator)

1. **Architect** builds a todo list, works through steps, completes work including specialists—but often **does not check off** the final **scribe** `.plan` artifact step, then prompts handoff to orchestrate.
2. **Orchestrate**, after switching from architect, **does not reliably create** its own todo list from the plan; it **jumps into execution** instead of reading **StagePlan** and tracking stages in the session todo UI.
3. Both agents should use the **same session todo system** the host provides (analogous to IDE “session todos”), not ad-hoc mental checklists in chat only.

---

## Design principles (final)

1. **Todos mirror protocol gates**, not generic “thinking” items.
2. **Update after every Task** (or equivalent subagent completion): mark the matching item **completed** with **`merge: true`** before the next Task or user-facing “done” message.
3. **Architect Mode A:** Item **Persist plan via `scribe` (primary `.plan`)** must be **completed** before **“Switch to `orchestrate`”**.
4. **Architect Mode B:** Separate todos for **`review` → `document` → each `scribe` doc write → `archive_plan`**; do not end the turn with **archive** still pending.
5. **Orchestrate:** After `.plan` path is fixed, todos include **`check-plan.sh`**, **one row per stage (+ verifier)**, **Difficulty completion gates**, **QA scribe** (if used), **architect handoff**—created **before** stage 1, even if the plan was already summarized in chat.
6. **GitHub backlog path** (when enabled in your stack): todos mirror **discover → implement → verify → transition → repeat** per issue.

---

## Files changed (this chat)

| File | Change |
| --- | --- |
| `agents/architect.md` | New section **Session progress todos**; new Hard Rule **14** |
| `agents/orchestrate.md` | New section **Session progress todos**; new Hard Rule **10** |
| `skills/architect-plan/SKILL.md` | **Session todos** under Feature Decomposition Protocol; Step 5 + non-feature scribe rule |
| `skills/orchestrate-execution/SKILL.md` | **Session todos** under Plan precondition; mark check-plan done before stage 1 |
| `skills/architect-review/SKILL.md` | **Session todos** under Mode B (archive gate on todo list) |

No changes to `opencode.json`, subagent permissions, or scribe agent mechanics.

---

## 1. `agents/architect.md`

**Insert** after the opening identity paragraph (`You are the Architect agent…`), before **Skill routing**:

### Section: Session progress todos (mandatory when multi-step)

```markdown
## Session progress todos (mandatory when multi-step)

When more than one substantive step remains in this episode (Claude Context gate, investigation, specialist Tasks, scribe writes, archive, user handoff), use the **host session todo** tool if the host exposes one (OpenCode / IDE todo list).

- **Create up front:** After you know the chain for this turn or episode, create todos for each step. Always include explicit items for **every `scribe` Task** you will run (primary `.plan` write, doc writes, `archive_plan`) and for **user handoff** where applicable.
- **Update after every Task:** Before starting the next Task or telling the user a step is done, refresh todos with **`merge: true`** — mark the step that just finished **completed**. Do not leave the **scribe primary `.plan`** item pending while you prompt handoff.
- **Mode A:** The item **Persist plan via `scribe` (primary `.plan` artifact + tool evidence)** must be **completed** before you prompt **Switch to `orchestrate`**. Treat forgotten todo updates the same as forgotten scribe: incomplete.
- **Mode B:** Include separate todos for **`review`**, **`document`**, each **`scribe`** doc write, and **`scribe` `archive_plan`** per **`architect-review`**. Do not declare Mode B finished while **archive_plan** is still pending on the todo list.
- **Single atomic step:** If only one Task remains for the whole reply and it completes in one shot, a minimal todo update is optional.
```

**Append** to **Hard Rules** (renumber if your file already has rule 14+):

```markdown
14. **Session todos.** Follow **Session progress todos** above whenever you use the host todo tool: never hand off to `orchestrate` while the **scribe primary `.plan`** step is still unchecked.
```

---

## 2. `agents/orchestrate.md`

**Insert** after `# Orchestrate Agent` intro, before **Skill routing**:

### Section: Session progress todos (mandatory when multi-step)

```markdown
## Session progress todos (mandatory when multi-step)

When a `.plan` artifact path is known (user choice, handoff, or bootstrap selection), use the **host session todo** tool if the host exposes one (OpenCode / IDE todo list).

- **After you have the artifact path:** Read enough of the plan to list **StagePlan** stages (stage ids) and any **Difficulty** completion gates. **Create** todos before the first `developer` precondition or stage Task — typical items: **`check-plan.sh` via `developer`**, **one todo per stage** (implement + verifier pass), **Difficulty gates** (`review` / `senior-dev` / `helper` when required), **QA scribe** (`.qa/<slug>.md` when orchestration completes), **handoff prompt to architect**.
- **Update after each gate:** After verifier **APPROVED**, after each difficulty gate, and after recovery amends, **`merge: true`** and mark the corresponding todo **completed** before advancing or summarizing.
- **Forbidden:** Starting stage 1 (or reporting "stage N complete") while the todo row for **plan precondition** or that stage is still unchecked if you are using todos this session.
- **Fresh switch from architect:** Even if the chat already summarized the plan, **still** derive todos from the **file** (read StagePlan) in this session — do not skip todo creation because the plan was "described" earlier.
```

**Append** to **Hard Rules**:

```markdown
10. **Session todos.** Follow **Session progress todos** above when using the host todo tool: after a `.plan` path is fixed, mirror **StagePlan** + gates in todos and sync after each verifier-approved stage.
```

*(If Hard Rules already use 10, use the next free number.)*

---

## 3. `skills/architect-plan/SKILL.md`

**After** the opening paragraph of **Feature Decomposition Protocol** (before **Step 0**), add:

```markdown
**Session todos:** If the host provides a todo tool, create todos for Steps 0–5 (investigation, strategist wave(s), merge/red-team, **Step 5 scribe + handoff**) and mark each **completed** immediately after that work finishes. The **scribe** item must be **completed** before the "Switch to `orchestrate`" prompt (see architect agent **Session progress todos**).
```

**Replace / extend** **Step 5: Scribe and handoff** closing sentence:

```markdown
Pass the feature plan to `scribe` via Task. After scribe success with tool evidence and no `SCRIBE_FAILED`, trust the write (see agent Hard Rules; design artifacts still need content drift check). **Mark the session todo for this scribe write completed**, then prompt user to switch to `orchestrate`.

**Other plan types** (debug/refactor/review/design): same rule — todo item for **`scribe` primary artifact** must flip to **completed** before handoff.
```

---

## 4. `skills/orchestrate-execution/SKILL.md`

**Inside** **Plan precondition (mandatory before the stage loop)**, after “When an artifact path is known…”, add:

```markdown
**Session todos:** If the host provides a todo tool, ensure todos exist for **this precondition**, **each StagePlan stage + verifier**, **Difficulty completion gates**, **final QA scribe**, and **architect handoff** — then keep them in sync after each step (see orchestrate agent **Session progress todos**).
```

**After** step 3 (“On success, continue to **Stage Loop**”), add:

```markdown
Mark the **check-plan** todo **completed** before starting stage 1.
```

---

## 5. `skills/architect-review/SKILL.md`

**After** the Mode B intro paragraph (first paragraph under **Mode B — Post-implementation**), add:

```markdown
**Session todos:** If the host provides a todo tool, create items for **`review` → `document` → each `scribe` write → `archive_plan`** and mark each **completed** as soon as that Task returns valid evidence. Do not end the turn with **`archive_plan`** still showing pending.
```

---

## Expected operator behaviour (after re-apply)

| Phase | Todo list should show |
| --- | --- |
| Architect planning | Investigation → strategists (if any) → merge → **scribe `.plan`** → handoff prompt |
| Architect Mode B | **review** → **document** → doc **scribe** writes → **archive_plan** |
| Orchestrate start | **check-plan** → **stage-1 … stage-N** → difficulty gates → QA → architect prompt |
| During orchestrate | Current stage in progress; prior stages **completed** on list |

---

## Verification checklist

Run from `~/.config/opencode`:

```bash
rg -l 'Session progress todos|host session todo' agents skills
```

Expect **five** paths:

- `agents/architect.md`
- `agents/orchestrate.md`
- `skills/architect-plan/SKILL.md`
- `skills/orchestrate-execution/SKILL.md`
- `skills/architect-review/SKILL.md`

**Smoke (manual):**

1. Architect: plan a small feature → confirm **scribe** todo completes before orchestrate handoff.
2. Orchestrate: select `.plan` → confirm todos appear **before** stage 1 and advance with verifier.
3. Architect Mode B: after orchestrate done → confirm **archive_plan** todo completes before “review cycle finished” message.

---

## Out of scope (this chat)

- Enabling or configuring a todo tool in `opencode.json` (host-dependent).
- Changes to **scribe**, **developer**, or **verifier** agents.
- **Mode F** GitHub feature sign-off todos (not in current slim `architect-review` skill; add similarly if Mode F is restored).
- Commits or PR creation (operator decision).

---

## Re-application note

If verification grep is empty, paste the sections above into the listed files (adjust Hard Rule numbers to match your file). This document is the canonical record for work completed **2026-05-18**; use that date in the filename prefix for this session, not the date you later filed the doc in `TO REVIEW`.
