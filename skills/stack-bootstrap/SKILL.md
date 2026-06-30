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
| `skills/setup-skills/templates/issue-tracker.md` | `docs/agents/issue-tracker.md` (set `SPEC_REPO:` line) |
| `skills/setup-skills/templates/triage-labels.md` | `docs/agents/triage-labels.md` |
| `skills/setup-skills/templates/domain.md` | `docs/agents/domain.md` |
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
