# GitHub Project Board

Org-wide portfolio view for PRD-driven work. **Real GitHub issues** appear on the board — not draft/project-only cards.

**Board:** [RoborewDev Project #1](https://github.com/orgs/RoborewDev/projects/1/views/1)

See also: [FEATURE-PIPELINE.md](FEATURE-PIPELINE.md) · [RUNBOOK.md](RUNBOOK.md)

---

## What appears on the board

| Item | Repo | Label | How it gets there |
|------|------|-------|-------------------|
| PRD parent issue | `*-spec` | `prd` | `opencode-run spec publish-prd-issue` |
| Child ticket issues | impl repos | `prd-task` | `opencode-run spec fanout` |

The PRD markdown file (`docs/prd/<slug>.md`) is **not** on the board. The parent GitHub issue links to it in the issue body.

Child issues are **sub-issues** of the PRD parent. Progress (e.g. 2/3 complete) rolls up on the parent card in the project view.

---

## Setup (one-time per machine)

### 1. Environment variable

Add to `~/.opencode-agent-env` (sourced by [scripts/agent-run.zsh](../scripts/agent-run.zsh)):

```bash
export GH_PROJECT="https://github.com/orgs/RoborewDev/projects/1"
# shorthand also works: export GH_PROJECT="RoborewDev/1"
```

When `GH_PROJECT` is unset, fanout and publish still work — they simply skip project registration (backward compatible).

### 2. GitHub CLI

```bash
gh auth refresh -s project
gh --version   # requires >= 2.94.0 for --parent / --add-sub-issue
```

### 3. Project auto-add workflows (one-time per repo)

In GitHub UI → **Project #1** → **Workflows** → **Auto-add**:

| Repo type | Filter |
|-----------|--------|
| Spec repo (`*-spec`) | `label:prd` |
| Each impl repo | `label:prd-task` |

Scripts also call `gh project item-add` when `GH_PROJECT` is set (belt-and-suspenders).

### 4. Sync tooling into spec repos

From the project parent:

```bash
setup-project
```

Commit and push the spec repo when `.github/workflows/prd-parent-auto-close.yml` is new.

---

## Pipeline integration

| Step | Script | Board action |
|------|--------|--------------|
| Publish PRD | `opencode-run spec publish-prd-issue` | Creates parent issue, sets `parent_issue` in PRD frontmatter, adds to board |
| Fanout | `opencode-run spec fanout <slug>` | Creates child issues as sub-issues, label `prd-task`, adds each to board |
| Re-run fanout | same | Idempotent: re-links existing issues, re-adds to board |
| All children closed | `prd-parent-auto-close` workflow | Hourly check; closes open PRD parent when all sub-issues are done |
| Feature done | `feature-complete` skill | Rollup comment + delivery record; close parent if still open |

---

## Smoke check

After fanout for a test slug:

```bash
gh project item-list 1 --owner RoborewDev --format json \
  | jq '.items[] | select(.content.type=="Issue") | .content.title'
```

On the PRD parent issue in GitHub, confirm sub-issues are listed and show completion progress.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Issues not on board | Set `GH_PROJECT`; run `gh auth refresh -s project` |
| Sub-issues not linked | Re-run `opencode-run spec fanout <slug>` (idempotent reconcile) |
| `gh issue create --parent` fails | Upgrade `gh` to >= 2.94.0 |
| Parent never auto-closes | Ensure `prd-parent-auto-close.yml` is in spec repo; sub-issues must be linked (not body-only references) |
