---
name: stack-bootstrap
description: Install OpenCode templates into one implementation repo path; optional legacy .plan/docs archive moves. Invoked only from setup-project via architect.
---

# Stack bootstrap

## Parent contract

The architect Task prompt must include:

- `local_path`: absolute path to **one** implementation git repo
- `spec_repo`: `owner/APP-spec` for `issue-tracker.md` substitution
- `operations`: list of `copy_templates` | `archive_legacy_plan` | `run_check`

## copy_templates

Resolve OpenCode config root as `OC="${OPENCODE_CONFIG:-$HOME/.config/opencode}"`.

Copy when missing or when parent says `force: true` for that file:

| Source | Destination (under `local_path`) |
|--------|----------------------------------|
| Inline GitHub ticket seed below | `docs/agents/issue-tracker.md` (set `SPEC_REPO:` line) |
| Inline triage-label seed below | `docs/agents/triage-labels.md` |
| Inline domain-doc seed below | `docs/agents/domain.md` |
| `templates/.github/ISSUE_TEMPLATE/child-feature.yml` | `.github/ISSUE_TEMPLATE/child-feature.yml` |
| `docs/templates/opencode.md.template` | `opencode.md` (only if missing) |

Do **not** create a `.opencode/` directory or `opencode.json` under the repo. Agents, MCP, and permissions live in **`$OPENCODE_CONFIG_DIR`** (default `~/.config/opencode`). Spec repos never carry project-level OpenCode config.

Ensure `.gitignore` contains:

```gitignore
tmp/
.research/
.qa/
.plan/*.completed.md
.opencode/
```

## archive_legacy_plan

When parent provides `source` and `dest` both under `local_path/.plan/`:

```bash
mkdir -p "$(dirname "$dest")"
mv "$source" "$dest"
```

Create `local_path/.plan/_archive/legacy/README.md` once:

```markdown
# Legacy plans

Archived during setup-project when work moved to GitHub issue-backed execution.
```

## run_check

```bash
"${OC}/bin/setup-project" --check-only "$(dirname "$(dirname "$local_path")")"
```

Return exit code and last 30 lines of output.

## Canonical inline seeds

The three `docs/agents/` seeds are defined here because they are shared by stack bootstrap and single-repository setup. Do not look for a second `skills/setup-skills/templates/` hierarchy.

### `docs/agents/issue-tracker.md`

```markdown
# Issue tracker

Issues for this repository are tracked on **GitHub**.

- **CLI:** `gh issue create`, `gh issue view`, `gh issue list`
- **Remote:** (fill from `git remote get-url origin`)
- **Spec repo:** (fill `SPEC_REPO:` when this is an implementation repo)
```

### `docs/agents/triage-labels.md`

```markdown
# Triage labels

| Role | Label on this repo |
|------|---------------------|
| Needs triage | needs-triage |
| Needs info | needs-info |
| Ready for agent | ready-for-agent |
| Ready for human | ready-for-human |
| Won't fix | wontfix |
```

### `docs/agents/domain.md`

```markdown
# Domain docs for agents

## Layout

- **Mode:** single-context | multi-context
- **Glossary:** `CONTEXT.md` at repo root (or see `CONTEXT-MAP.md` for paths)
- **ADRs:** `docs/adr/` (system-wide); bounded contexts may use `<context>/docs/adr/`

## Consumer rules

1. Before naming entities in tickets, read the active `CONTEXT.md`.
2. Before changing architecture, scan `docs/adr/` for decisions in that area.
3. `CONTEXT.md` is glossary-only, not implementation specs.
```
