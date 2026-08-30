---
name: to-tickets
description: Break a plan, spec, or PRD into independently-grabbable GitHub tickets using tracer-bullet vertical slices. Use when the user wants to convert a plan into tickets, create implementation tickets, or break work into tickets.
---

# To Issues

Break work into independently-grabbable **GitHub tickets** using **vertical slices** (tracer bullets). Primary path for **targeted changes**, debug fixes, refactor slices, and **Prototype Design** flows.

**Architect delegation:** publish via `bin/publish-targeted-issue` (bash). Never `gh issue create`. File drafts → Task **scribe** first if a body file must exist on disk.

## Prototype Design

When the user asks for "prototype design" / "design prototype", or selects Prototype Design (impl menu option 6 in legacy terms — load `to-tickets` directly here):

1. **Prompt for design intake** (required before invoking `designer`). Collect, with confirmation when ambiguous:
   - Site purpose and audience
   - Desired feel (e.g., minimal, bold, playful, corporate)
   - Color scheme and palette
   - Prototype output mode: Vanilla HTML5 only (framework-agnostic)
   - Icon set (e.g., Lucide, Heroicons)
   - Required sections (e.g., hero, feature grid, pricing table)
   - Accessibility expectations (WCAG AA minimum)
   - Reference asset paths: prompt the user to upload or provide paths to reference images/files
2. **Invoke `designer`** subagent with the collected intake and any reference paths. `designer` returns a read-only design brief; no code.
3. **Embed the brief** in the GitHub issue's `## Implementation plan`; set `design_delivery: prototype-required` in the issue body's `opencode-task-yaml`.
4. **Add ordered issue stages** in `opencode-task-yaml` `stages[]`:
   - `ux-prototype` owned by `ux-dev`
   - `react-implementation` owned by `frontend-dev` with `depends_on: [ux-prototype]`
5. **Emit the execution handoff** to a new `orchestrate` session in the impl repo. Orchestrate dispatches `ux-dev` to build `.prototype/<slug>/`, then `frontend-dev` implements the approved design in React.

## Preconditions

- Read `docs/agents/issue-tracker.md` and `docs/agents/triage-labels.md` when present (from **`setup-skills`** or **`setup-project`**).
- For spec-driven features, use spec fanout + **issue-expand** instead — this skill is for **targeted** or ad-hoc work in an implementation repo.
- Optional: conversation context or a research note — not a required `.plan` file.

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

**Targeted issue publisher (required):**

- Use `bin/publish-targeted-issue` for targeted/ad-hoc issues.
- Do **not** call raw `gh issue create`; architect permissions deny it to preserve PRD/fanout guardrails.
- Use `opencode-run spec fanout` for PRD child issues and `opencode-run spec publish-prd-issue` for PRD parent issues.

**`remediation:` issues (feature coder):**

When publishing remediation tickets for unmet acceptance or cross-ticket findings surfaced by the feature coder's `feature-review` loop:

- Create issues in the **impl** repo (`--repo owner/name`).
- Link as **sub-issues** of the Spec PRD parent: `--parent-issue <url from docs/prd/<slug>.md frontmatter>`.
- Title prefix: `remediation: <short title>`.
- Labels: `feature:<slug>`, `prd-task`, `state:ready-for-agent`, `category:chore` (or appropriate category).
- `task_id`: `remediation-<slug>-<n>` in issue body yaml.
- Body must embed `opencode-task-yaml` with `stages[]` (same shape as the original ticket) and acceptance criteria.
- After publish, the feature coder returns `BLOCKED: FEATURE_REMEDIATION` with the issue numbers; the develop orchestrator re-batches them through the normal ticket pipeline.

```bash
bin/publish-targeted-issue \
  --repo <impl_owner/name> \
  --title "remediation: <title>" \
  --feature-slug "<slug>" \
  --parent-issue "<prd_parent_issue_url>" \
  --label "state:ready-for-agent" \
  --label "prd-task" \
  --body-file -
```

**Duplicate guard (handled by `bin/publish-targeted-issue`, still required conceptually):**

- List existing issues for the feature slug: `gh issue list --repo <owner/name> --state all --label "feature:<slug>" --limit 200 --json number,title,body` (caps at 200 per `gh issue list`; for exhaustive duplicate checks on very large features, use `gh api repos/<owner>/<name>/issues --paginate` with the same label filter instead)
- **Do not create** if an open or closed issue already has the same exact **title** or the same **`task_id`** in an `opencode-task-yaml` fence.
- If the approved breakdown itself contains duplicate titles, stop and ask the user to merge, rename, or split before publishing.
- If publishing is interrupted and resumed, re-run the guard before **each** create — never assume a prior create failed.
- Publish **sequentially** (one issue at a time); do not parallelize creates for the same slug.

For each approved slice:

```bash
bin/publish-targeted-issue \
  --title "..." \
  --body-file - \
  --feature-slug "<slug>" \
  --label "state:ready-for-agent" \
  --label "category:chore" <<'EOF'
## What to build
...

## Acceptance criteria
- [ ] ...
- [ ] ...

## Blocked by
- #NNN or None — can start immediately
EOF
```

Apply the triage label for AFK-ready work (default: `state:ready-for-agent`) and `category:feature` or `category:chore` as appropriate. Include **`opencode-task-yaml`** fence in the body when orchestrate will execute the issue (minimal meta: `task_id`, `owner`, `acceptance`, `test_commands`; add `stages[]` when multi-step TDD is required).

**Do not** write local `.plan` files — issues are the source of truth.

After publish, emit the architect agent **execution handoff** verbatim: use the **feature backlog** variant when issues share `feature:<slug>`; otherwise the **targeted queue** variant with issue numbers. Do not say only “switch to orchestrate.”

### Default triage labels (when `docs/agents/triage-labels.md` absent)

- `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix` — map per repo convention when documented.
