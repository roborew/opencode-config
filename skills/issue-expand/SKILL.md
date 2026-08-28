---
name: issue-expand
description: Implementation technical planning on GitHub issues — codebase-backed plans, readable markdown, stages for orchestrate. Runs from spec repo (after fanout) or impl repo (deprecated fallback).
modelTier: smart
roleReminder: "Spec or impl repo. Run read-only opencode-run impl/* via bash (use --cwd for impl siblings from spec). Task developer for gh issue edits with explicit repo; Task scribe for files — never raw gh/git/file mutations."
---

# Issue expand (implementation technical planning)

Phase 4 of the feature pipeline: turn spec fanout tickets into **developer-reviewable implementation plans** on each GitHub issue, then gate orchestrate.

**The user does not run project automation.** You run **read-only** `opencode-run impl/*` validators via bash. **Task developer** for `gh issue edit`; **Task scribe** for any file write. The user approves each issue edit and switches to **orchestrate** when you prompt.

## When

- **Spec repo:** architect option 1 continuation immediately after fanout (same session).
- **Impl repo (deprecated):** front-door option 8 — prefer spec option 1 for issue-expand.
- User gives **feature slug** (kebab-case, same as `feature:<slug>` label).
- Open issues exist from spec fanout.

## Hard rules (non-negotiable)

- **You** run bundle, feature-check, orchestrate-readiness-check, and optional feature-context — **never** paste these as instructions for the user.
- **Never** prompt orchestrate because gates passed if **Implementation plan** is still placeholder or lacks **Context**, **Current state**, **Stage plan**, and **Tests**.
- **Never** treat existing production code as "ticket done" — map each requirement to tests or an explicit gap.
- If bundle fails, read `tmp/issue-expand-bundle.md` and fix/sync — do not ask the user to run the same commands.
- **Never** use `2>/dev/null`, `>`, or `>>` in bash (architect deny rules). Run opencode-run bare.
- **Human approval** required before each `gh issue edit` (Task **developer** with explicit `repo: owner/name`).

## Multi-repo loop (spec repo)

1. Read PRD `tickets[]` from `docs/prd/<slug>.md`; group by `repo`; order repos and tickets by `depends_on` (same order as fanout).
2. For each impl repo in that order:
   - Resolve absolute path: `source "$OC/bin/project/spec/lib/resolve_impl_path.sh"` then `_resolve_impl_path owner/repo` (or run the script).
   - Run bundle and gates with `--cwd "$IMPL_ABS_PATH"` (see workflow below).
3. After **all** repos pass gates, run once: `opencode-run spec feature-check <slug> --level orchestrate`.
4. Emit **one execution handoff per impl repo** (see architect agent handoff template with Impl repo / Impl path / Depends on / Parallel OK).

**Fanout → expand continuity (token economy):** Do not re-paste the full PRD. Use the fanout summary table (parent URL, repo#issue# map), `docs/prd/<slug>.md`, and per-repo `tmp/issue-expand-bundle.md`. Load per-ticket detail only when drafting that ticket.

## Workflow (architect executes)

### 1. Bootstrap — per impl repo

From **spec repo:**

```bash
opencode-run --cwd "$IMPL_ABS_PATH" impl issue-expand-bundle <slug>
```

From **impl repo** (deprecated): `opencode-run impl issue-expand-bundle <slug>`.

Read `tmp/issue-expand-bundle.md` under that impl repo (path: `$IMPL_ABS_PATH/tmp/issue-expand-bundle.md` when expanding from spec). PRD loads from local spec sibling, `SPEC_PRD_REF`, or GitHub. Optional per ticket: `opencode-run --cwd "$IMPL_ABS_PATH" impl feature-context <n>`.

### 2. Claude Context (mandatory, per impl repo)

Index **once per impl repo per session**, not per ticket:

```
get_indexing_status({ path: IMPL_ABS_PATH })
index_codebase({ path: IMPL_ABS_PATH })  # if needed
search_code({ path: IMPL_ABS_PATH, query: "..." })
```

Record `MCP_FALLBACK` and use `rg`/`find` on `$IMPL_ABS_PATH` if MCP unavailable.

### 3. Per open issue (dependency order)

For each issue in this repo (respect **Blocked by** / `depends_on`):

1. Read PRD slice + **Requirements** + **Description** from the bundle.
2. **Investigate** the codebase at `IMPL_ABS_PATH` — document **Current state** and gaps.
3. Draft **Implementation plan** (readable markdown under `## Implementation plan`):

```markdown
### Context
### Goal
### Current state
### Stage plan
### Files to change
### Tests
### Refactor / risks
```

4. If design uncertainty required `designer`, embed its brief in the Implementation plan and set `design_delivery` to `brief-only` or `prototype-required`. For `prototype-required`, build ordered stages with `ux-prototype` owned by `ux-dev` and `react-implementation` owned by `frontend-dev`, with the latter depending on the former. For `brief-only`, route directly to `frontend-dev`.
5. Build **`opencode-task-json`** `stages[]` from the stage plan (validator reads JSON fence).
5. Show the human a concise summary → on approval → Task **developer** `load: minimal` with `repo: owner/name` → `gh issue edit <n> --repo owner/name --body-file …`.

### 4. Gates — you run

Per impl repo:

```bash
opencode-run --cwd "$IMPL_ABS_PATH" impl feature-check <slug> --level orchestrate
opencode-run --cwd "$IMPL_ABS_PATH" impl orchestrate-readiness-check <slug>
```

After all repos:

```bash
opencode-run spec feature-check <slug> --level orchestrate
```

All must **PASS** with substantive plans. If FAIL, continue planning — do not hand off to orchestrate.

### 5. Handoff (user action only)

Emit the architect agent **execution handoff** — **one per impl repo**, in PRD dependency order. Include Impl repo, Impl path, Depends on, Parallel OK. Mark `Parallel OK: yes` when no cross-repo `depends_on` blocks remain for that repo's tickets.

Do not list shell commands. Do not say only “switch to orchestrate.”

## Issue body (target)

| Section | Owner | Content |
|---------|-------|---------|
| User stories covered | spec | PRD mapping |
| Requirements | spec | Product outcomes |
| Implementation plan | **you** | Context, Current state, Stage plan, Tests |
| opencode-task-json | **you** | `task_id`, `owner`, `depends_on`, `stages[]`, `acceptance`, `test_commands`, `commit_message` |

## PRD changed after fanout

User works in **spec** repo (`feature-upgrade` or edit PRD). Re-run **issue-expand** from spec option 1 with the updated slug.

## Boundaries

- Do not invoke **orchestrate** from this skill.
- Do not invoke **scribe** to write `.plan/feature.*` or `.plan/issue.*` on this path.
