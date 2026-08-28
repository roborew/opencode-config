---
name: setup-skills
description: Scaffold per-repo agent context — GitHub ticket tracker, triage labels, domain doc layout — under docs/agents/ and an AGENTS.md or README section. Run once per repo before relying on to-tickets, grill-me CONTEXT persistence, or cross-session portability.
---

# Setup skills (per-repo)

Scaffold the configuration that **`grill-me`**, **`to-tickets`**, **`debug-fix`**, and **`zoom-out`** assume:

- **Ticket tracker** — where GitHub tickets live (GitHub is required for this configuration)
- **Triage labels** — strings for agent-ready vs human-needed work
- **Domain docs** — single `CONTEXT.md` + `docs/adr/` vs multi-context `CONTEXT-MAP.md`

This is a **prompt-driven** skill: explore the repo, present findings, confirm with the user, then persist via **`scribe`** (Task `scribe` with `target_path` + full `content`). Do not invent remote URLs; read `git remote -v` when relevant.

## Process

### 1. Explore

- `git remote -v` — GitHub? GitLab? none?
- Root `README.md`, `AGENTS.md`, `CLAUDE.md` — is there already an `## Agent skills` block?
- `CONTEXT.md`, `CONTEXT-MAP.md`, `docs/adr/`, `docs/agents/`

### 2. Present and confirm (one topic at a time)

**A — Ticket tracker.** This configuration uses **GitHub**. Confirm the remote and record it in `issue-tracker.md`; do not offer local-markdown, GitLab, or freeform tracker alternatives.

**B — Triage labels.** Canonical five (map to repo labels if different):

| Role | Default string |
|------|------------------|
| Maintainer must evaluate | `needs-triage` |
| Waiting on reporter | `needs-info` |
| AFK agent can pick up | `ready-for-agent` |
| Needs human implementation | `ready-for-human` |
| Won't fix | `wontfix` |

**C — Domain layout.** **Single-context** — one `CONTEXT.md` at repo root + `docs/adr/`. **Multi-context** — `CONTEXT-MAP.md` at root pointing to per-context `CONTEXT.md` and optional per-context `docs/adr/`.

### 3. Draft for user edit

Show drafts of:

1. `docs/agents/issue-tracker.md`
2. `docs/agents/triage-labels.md`
3. `docs/agents/domain.md`
4. A short `## Agent skills` markdown block (for `AGENTS.md` **or** `README.md`)

### 4. Write via scribe

Invoke **`scribe`** three times (or one batched sequence per parent rules) with:

- `target_path: docs/agents/issue-tracker.md`
- `target_path: docs/agents/triage-labels.md`
- `target_path: docs/agents/domain.md`

Then either:

- **`target_path: AGENTS.md`** — create or append `## Agent skills` (if creating, include a one-line title at top: `# Agent notes`), **or**
- Append the same block to **`README.md`** if the user prefers no new file.

Never create both `AGENTS.md` and duplicate the block in `README.md`.

### 5. Done

Tell the user setup is complete. They can edit `docs/agents/*.md` anytime. Re-run this skill when switching issue tracker or domain layout.

---

## Seed: `docs/agents/issue-tracker.md` (GitHub)

```markdown
# Issue tracker

Issues for this repository are tracked on **GitHub**.

- **CLI:** `gh issue create`, `gh issue view`, `gh issue list`
- **Remote:** (fill from `git remote get-url origin`)

Non-GitHub workflows belong in this file as plain-English steps for agents.
```

## Seed: `docs/agents/triage-labels.md`

```markdown
# Triage labels

| Role | Label on this repo |
|------|---------------------|
| Needs triage | needs-triage |
| Needs info | needs-info |
| Ready for agent | ready-for-agent |
| Ready for human | ready-for-human |
| Won't fix | wontfix |

When creating issues, use the **Label on this repo** column. If a label does not exist yet, create it or omit and note in the issue body.
```

## Seed: `docs/agents/domain.md`

```markdown
# Domain docs for agents

## Layout

- **Mode:** single-context | multi-context
- **Glossary:** `CONTEXT.md` at repo root (or see `CONTEXT-MAP.md` for paths)
- **ADRs:** `docs/adr/` (system-wide); bounded contexts may use `<context>/docs/adr/`

## Consumer rules

1. Before naming entities in plans or issues, read the active `CONTEXT.md`.
2. Before changing architecture, scan `docs/adr/` for decisions in that area.
3. `CONTEXT.md` is glossary-only — not implementation specs.
```

## Seed: `## Agent skills` block

```markdown
## Agent skills

### Issue tracker

Configured for this repo. See `docs/agents/issue-tracker.md`.

### Triage labels

See `docs/agents/triage-labels.md`.

### Domain docs

See `docs/agents/domain.md`.
```
