# Feature pipeline

Spec-driven path from PRD to orchestrate-ready GitHub issues. **Agents run `bin/*`; humans run `setup-project` once, then use OpenCode menus.**

## Flow (what happens, not what you type)

| # | Where | Who does it |
|---|--------|-------------|
| 1 | spec | User + **architect**: grill-me → to-prd → approve PRD |
| 2 | spec | **architect** (fanout-issues): creates child issues per repo |
| 3 | impl | User: **architect option 1** + slug → **issue-expand** runs bundle, plans each issue, gates |
| 4 | impl | User approves issue edits in chat → **architect** runs checks → prompts **orchestrate** |
| 5 | impl | **orchestrate** exhausts `feature:<slug>` queue → push + ready-for-review PR (unless opted out) → **new session** → **architect** Mode F sign-off → human merge PR |
| 6 | spec | **feature-complete** after all impl repos signed off (closes PRD parent issue) |

### Session boundaries (recommended)

- **Planning (issue-expand):** architect session in each impl repo.
- **Execution:** **new** OpenCode session → orchestrate with `feature:<slug>` only (issues + YAML are source of truth).
- **Review:** **new** session → architect impl repo **option 5** with slug + PR URL from orchestrate.

Same-session handoff is optional (`/compact` after a short HANDOFF block); use a new session if the provider errors on tool history.

### Sign-off and ticket closure

| Label / state | Set by | Meaning |
|---------------|--------|---------|
| `state:in-progress` | orchestrate | Actively executing issue/stages |
| `state:ready-for-review` | orchestrate (verifier PASS) | Implementation done; awaiting architect/human |
| `state:done` | architect Mode F | Accepted after review vs PRD/tickets |
| Issue **closed** on GitHub | architect Mode F (via **developer** `gh`) | Ticket complete |

Orchestrate does **not** close issues as done. Per-issue commits happen during execution; one **feature PR** is opened when the queue is empty (`feature-finish-pr.sh`).

**Mode F** (GitHub-first): architect compares closed/`state:done` issues and acceptance vs `$SPEC_REPO/docs/prd/<slug>.md` when `SPEC_REPO` is set; runs **review** subagent; may **document** + **scribe**; no `.plan` archive unless a local plan was executed.

**Mode B** (legacy `.plan`): after local plan execution — review, docs, **`archive_plan`** to `*.completed.md`.

**Remediation:** review requests fixes → architect **to-issues** or review sidecar → **orchestrate** again (prefer new session).

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
