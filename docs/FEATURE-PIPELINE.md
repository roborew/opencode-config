# Feature pipeline

Spec-driven path from PRD to orchestrate-ready GitHub issues. **Agents run `bin/*`; humans run `setup-project` once, then use OpenCode menus.**

## Flow (what happens, not what you type)

| # | Where | Who does it |
|---|--------|-------------|
| 1 | spec | User + **architect**: grill-me → to-prd → approve PRD |
| 2 | spec | **architect** (fanout-issues): creates child issues per repo |
| 3 | impl | User: **architect option 1** + slug → **issue-expand** runs bundle, plans each issue, gates |
| 4 | impl | User approves issue edits in chat → **architect** runs checks → prompts **orchestrate** |
| 5 | impl | **orchestrate** → PR → **architect** sign-off → **feature-complete** in spec |

## Two execution modes

| Mode | Where | Source of truth | Architect entry |
|------|--------|-----------------|-----------------|
| **Spec / GitHub** (default) | spec + impl repos | GitHub issues with `feature:<slug>` after fanout + issue-expand | Impl repo **option 1** |
| **Legacy local plan** | single impl repo | `.plan/feature.<slug>.md` | Impl repo **option 2** |

Fanout alone is not enough for the stage loop — **issue-expand** is mandatory before orchestrate on the spec path.

## One human shell command (stack bootstrap)

From the **project parent** (folder containing `*-spec` and impl repos):

```bash
export GH_ORG=your-github-login-or-org
cd ~/code/APP && setup-project
```

`GH_ORG` is the GitHub **owner** (`owner/repo`), not the app slug or local folder name. That syncs tooling into spec + impl repos. Everything else is OpenCode agents and skills. See [RUNBOOK.md](RUNBOOK.md) and [skills/setup-project/SKILL.md](../skills/setup-project/SKILL.md).

## Responsibility split

| Phase | Repo | Owns |
|-------|------|------|
| Requirements | spec | User stories, product acceptance, repo tickets, blockers |
| Technical planning | impl | **issue-expand** (agent): Context, stages, tests, `opencode-task-yaml` |

## Canonical issue body

Parent PRD · User stories · Requirements · **Implementation planning** · **opencode-task-yaml** · Description · Blocked by

Details: [plan-artifact-schema.md](plan-artifact-schema.md).

## Internal scripts (agents only)

Synced to each repo for architect/orchestrate — **not** a user runbook:

| Script | Used by |
|--------|---------|
| `bin/issue-expand-bundle` | issue-expand |
| `bin/feature-check` | issue-expand, feature-upgrade |
| `bin/orchestrate-readiness-check` | issue-expand |
| `bin/feature-context` | issue-expand, orchestrate |
| `bin/fanout` | fanout-issues (spec) |

## See also

- [RUNBOOK.md](RUNBOOK.md)
- [skills/issue-expand/SKILL.md](../skills/issue-expand/SKILL.md)
- [skills/setup-project/SKILL.md](../skills/setup-project/SKILL.md)
