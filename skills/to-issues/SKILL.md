---
name: to-issues
description: Break a plan, spec, or PRD into independently-grabbable GitHub issues using tracer-bullet vertical slices. Use when the user wants to convert a plan into issues, create implementation tickets, or break work into GitHub issues.
---

# To Issues

Break a plan into independently-grabbable issues using **vertical slices** (tracer bullets).

## Preconditions

- Prefer an existing `.plan/<type>.<slug>.md` as source of truth.
- If this repo has `docs/agents/issue-tracker.md` and `docs/agents/triage-labels.md` (from **`setup-skills`**), read them and follow the issue tracker + label mapping. If missing, default to **GitHub** on the current `origin` remote using `gh issue create` and label names from the triage section below.

## Process

### 1. Gather context

Work from the plan artifact and conversation. If the user passed an issue URL or number, fetch it with `gh issue view` when using GitHub.

### 2. Explore the codebase (optional)

If titles should reflect real modules, skim the codebase. Use vocabulary from `CONTEXT.md` / `CONTEXT-MAP.md` and respect ADRs under `docs/adr/`.

### 3. Draft vertical slices

Break the plan into **tracer bullet** issues. Each issue is a thin vertical slice through **all** integration layers end-to-end, not a horizontal layer-only ticket.

- Each slice delivers a narrow but **complete** path (schema, API, UI, tests where applicable).
- A completed slice is demoable or verifiable on its own.
- Prefer many thin slices over few thick ones.
- Tag each slice **HITL** (needs human decision / design / access) or **AFK** (agent can implement without extra human context).

### 4. Quiz the user

Present the breakdown as a numbered list. For each slice show:

- **Title**
- **Type**: HITL / AFK
- **Blocked by**: other slice numbers or "None"
- **User stories / plan sections** covered

Ask: granularity OK? Dependencies correct? Any merge/split? HITL/AFK correct?

Iterate until the user approves.

### 5. Publish (GitHub)

Publish in **dependency order** (blockers first) so "Blocked by" can cite real issue numbers.

For each approved slice:

```bash
gh issue create --title "..." --body-file - <<'EOF'
## What to build
...

## Acceptance criteria
- [ ] ...
- [ ] ...

## Blocked by
- #NNN or None — can start immediately
EOF
```

Apply the triage label for AFK-ready work (default: `ready-for-agent`) if that label exists on the repo; otherwise omit labels and note that in the handoff.

**Do not** close or rewrite the parent plan file; issues are additive.

### Default triage labels (when `docs/agents/triage-labels.md` absent)

- `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix` — map per repo convention when documented.
