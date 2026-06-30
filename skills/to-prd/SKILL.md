---
name: to-prd
description: "Synthesise a PRD from grill-me / research context, write docs/prd/<slug>.md, publish a GitHub issue with prd + state:ready-for-agent + feature:<slug>. Halt after publish — do not invoke fanout."
modelTier: smart
roleReminder: "Run after grill-me when the feature is understood. Scribe writes files; you use gh for the issue or delegate to developer."
---

# To PRD

Publish a **human-reviewable PRD** before vertical slicing. This closes the gap where local `.plan` artifacts are not the product record.

## Preconditions

- `gh` CLI authenticated (`gh auth status`).
- Current repo is the **spec repo** or the repo where PRDs live (`docs/prd/` exists or will be created).
- **`docs/agents/repos.md`** must list every target implementation repo with `application_role`, `agent_owner`, and `capabilities`. If empty or incomplete, run **`setup-project`** or update the registry via scribe **before** drafting PRD tickets.
- Optional: `.research/<slug>.md` from the `research` skill — load and cite in **Linked artifacts**.
- Optional: **`CONTEXT.md`** for product vocabulary (terms only — repo topology lives in `docs/agents/repos.md`).

## Behaviour

1. **Architecture gate:** Read `docs/agents/repos.md`. Present a summary table: repo, `application_role`, key `capabilities`, `non_goals`. Ask: **"Is this architecture correct for this feature?"** If `repos:` is empty or a needed repo is missing, stop and collect roles/capabilities from the user (via scribe update to `docs/agents/repos.md`) before continuing.
2. **Inputs:** feature name, kebab-case `<slug>`, and any user/stakeholder notes from the session.
3. **Compose** the PRD body using `skills/to-prd/templates/prd.md` — all sections must be present (use `TBD` only where the human must fill later; prefer concrete content from the session). Include **Architecture confirmation** referencing the registry.
4. **Draft tickets (when slicing in same session):** Each ticket must include `repo`, **`capability`** (from that repo's registry entry), `title`, `owner` (match registry `agent_owner` unless justified), and **`acceptance`** as **product outcomes** (not file paths or shell commands). **Do not** put `test_commands` or `commit_message` in PRD tickets — implementation **issue-expand** discovers those from the codebase. **Do not** assign work by inferring backend/frontend from repo names.
5. **YAML frontmatter rules (mandatory before scribe):** Ticket fields under `tickets:` must stay **indented 4 spaces** under each `- id:` item. Quote `title` when it contains `:`. After composing, validate with `python3 bin/lib/validate_prd_frontmatter.py docs/prd/<slug>.md` — do not invoke scribe until it exits 0.
6. **Invoke `scribe`** to write `docs/prd/<slug>.md` with the full markdown (verbatim template structure including frontmatter).
7. **Create GitHub issue** in this spec repo via **`bin/publish-prd-issue`** (not raw `gh issue create`):
   - Write the filled body to a temp file, then:
   ```bash
   bin/publish-prd-issue <slug> "[PRD] <slug>: <one-line summary>" /path/to/body.md
   ```
   - Body: use `skills/to-prd/templates/prd-issue.md` filled with the same sections (or link to `docs/prd/<slug>.md` path in repo + paste summary).
   - `bin/publish-prd-issue` writes `parent_issue` into `docs/prd/<slug>.md` frontmatter and adds the parent issue to the org project board when `GH_PROJECT` is set.
8. **Stop.** Tell the user: "PRD published — **human review required**. Do not run fanout until you approve the PRD, ticket repo/capability mapping, and PRD issue body. Confirm `parent_issue` is set in the PRD frontmatter (the publish script sets this automatically)." Include **Parent issue URL** and **Project board** (`$GH_PROJECT` or "skipped") in the reply.

## Hard rules

- **Do not** invoke `fanout`, `orchestrate`, or write `.plan` artifacts from this skill.
- **Scribe** is the only writer for `docs/prd/*.md` and `docs/agents/repos.md`.
- **Do not** infer repo responsibilities from names or folder layout; use `docs/agents/repos.md`.
- If `docs/prd/` is missing, scribe creates the directory by writing the file path.

## Label fallbacks

If `state:ready-for-agent` does not exist, use the canonical state label from `docs/agents/triage-labels.md` for "AFK agent can pick up" and note the substitution in the reply.
