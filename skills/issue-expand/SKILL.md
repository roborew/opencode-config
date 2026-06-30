---
name: issue-expand
description: Implementation technical planning on GitHub issues — codebase-backed plans, readable markdown, YAML stages for orchestrate. Spec fanout only captures requirements.
modelTier: smart
roleReminder: "Implementation repo. Run read-only bin/* via bash. Task developer for gh issue edits; Task scribe for files — never raw gh/git/file mutations."
---

# Issue expand (implementation technical planning)

Phase 4 of the feature pipeline: turn spec fanout tickets into **developer-reviewable implementation plans** on each GitHub issue, then gate orchestrate.

**The user does not run `bin/*` in this repo.** You run **read-only** `bin/*` validators via bash. **Task developer** for `gh issue edit`; **Task scribe** for any file write. The user approves each issue edit and switches to **orchestrate** when you prompt.

## When

- Implementation repo front-door **option 1** (spec workflow / issue-expand).
- User gives **feature slug** (kebab-case, same as `feature:<slug>` label).
- Open issues exist from spec fanout.

## Hard rules (non-negotiable)

- **You** run `bin/issue-expand-bundle`, `bin/feature-check`, `bin/orchestrate-readiness-check`, and optional `bin/feature-context` — **never** paste these as instructions for the user.
- **Never** prompt orchestrate because gates passed if **Implementation planning** is still placeholder or lacks **Context**, **Current state**, **Stage plan**, and **Tests**.
- **Never** treat existing production code as "ticket done" — map each requirement to tests or an explicit gap.
- If bundle fails, read `tmp/issue-expand-bundle.md` (Errors section) and fix/sync — do not ask the user to run the same commands.
- **Never** use `2>/dev/null`, `>`, or `>>` in bash (architect deny rules). Run bins bare.
- **Human approval** required before each `gh issue edit` (Task **developer**).

## Workflow (architect executes)

### 1. Bootstrap — you run

`bin/issue-expand-bundle <slug>`  
Read `tmp/issue-expand-bundle.md`. PRD file is loaded from the **local spec sibling checkout**, else `SPEC_PRD_REF` in `docs/agents/issue-tracker.md` (e.g. `develop`), else `develop`/`main` — **not** spec default branch only. If the file is missing, the bundle still lists **GitHub child issues** and the parent PRD issue from `Parent PRD:` lines. Optional per ticket: `bin/feature-context <n>`.

### 2. Claude Context (mandatory)

`get_indexing_status` → `index_codebase` if needed. Use `search_code` / `find_files` per ticket. Record `MCP_FALLBACK` if unavailable.

### 3. Per open issue (dependency order)

For each issue (respect **Blocked by** / `depends_on`):

1. Read PRD + **Requirements** + **Description** from the bundle.
2. **Investigate** the codebase — document **Current state** and gaps.
3. Draft **Implementation planning** (readable markdown):

```markdown
### Context
### Goal
### Current state
### Stage plan
### Files to change
### Tests
### Refactor / risks
```

4. Build **`opencode-task-yaml`** `stages[]` from the stage plan.
5. Show the human a concise summary → on approval → Task **developer** `load: minimal` → `gh issue edit <n> --body-file …`.

### 4. Gates — you run

`bin/feature-check <slug> --level orchestrate`  
`bin/orchestrate-readiness-check <slug>`

Both must **PASS** with substantive plans. If FAIL, continue planning — do not hand off to orchestrate.

### 5. Handoff (user action only)

Emit the architect agent **execution handoff** verbatim (feature backlog variant). Example for slug `google-auth`:

````markdown
## Execution handoff

| Field | Value |
|-------|-------|
| Feature | `Google Auth` |
| Slug | `feature:google-auth` |
| Queue source | GitHub issues with label `feature:google-auth` |
| Next agent | `orchestrate` in a new session |
| First message | `feature:google-auth` |

| Review before starting | Status / note |
|------------------------|---------------|
| Issue expansion | `PASS` |
| Readiness gates | `PASS` |
| Key risks / constraints | `None` |

Copy/paste into the new `orchestrate` chat:
```text
feature:google-auth
```
````

Do not list shell commands. Do not say only “switch to orchestrate.”

## Issue body (target)

| Section | Owner | Content |
|---------|-------|---------|
| User stories covered | spec | PRD mapping |
| Requirements | spec | Product outcomes |
| Implementation planning | **you** | Context, Current state, Stage plan, Tests |
| opencode-task-yaml | **you** | `task_id`, `owner`, `depends_on`, `stages[]` |

Legacy **`opencode-task-json`** fences are read during migration only; new writes use **`opencode-task-yaml`**.

## PRD changed after fanout

User works in **spec** repo (resync or `feature-complete` path). You re-run **issue-expand** here when they return with an updated slug.

## Boundaries

- Do not invoke **orchestrate** from this skill.
- Do not invoke **scribe** to write `.plan/feature.*` or `.plan/issue.*` on this path.
