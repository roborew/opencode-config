---
name: fanout-issues
description: "Cross-repo companion to to-prd: after PRD frontmatter is filled, run bin/fanout <slug> from this spec repo to create child GitHub issues (one per ticket or legacy slice)."
modelTier: "fast"
roleReminder: "Operates in the application spec repo; uses gh + yq."
---

# Fanout issues

## When

`docs/prd/<slug>.md` has valid YAML frontmatter with **`tickets:`** (preferred) or legacy **`slices:`**, plus `parent_issue` and `target_repos` as defined in `docs/prd/_template.md`.

## How

From this repo root:

```bash
bin/fanout <slug>
```

## Rules

### `tickets:` (preferred)

- Each ticket row becomes **one** child issue in the repo named by `repo` (full `owner/repo` matching `docs/agents/repos.md`).
- Issues are created in **dependency order** (`depends_on` task ids).
- Labels include `feature:<slug>`, `state:ready-for-agent`, `mode:afk` or `mode:hitl`, and `category:feature`.
- The issue body embeds fenced **`opencode-task-json`** metadata (task id, acceptance, `test_commands`, `commit_message`, etc.) plus human-readable sections.

### Legacy `slices:`

- Each slice key must be a **full** `owner/repo` string matching `docs/agents/repos.md`.
- One broad issue per repo (same label set where applicable).
