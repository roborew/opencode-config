# OpenCode Agent Orchestration

Stage-based **Architect → Orchestrate → subagents** pipeline with model routing in [`opencode.json`](opencode.json). **Canonical operational detail:** [`docs/RUNBOOK.md`](docs/RUNBOOK.md). **Capability matrix:** [`docs/architecture/opencode-capability-matrix.md`](docs/architecture/opencode-capability-matrix.md).

## Quick reference

| Topic | Location |
|--------|----------|
| Pipeline, grading, MCP policy | [`docs/RUNBOOK.md`](docs/RUNBOOK.md) |
| Per-project context template | [`docs/templates/opencode.md.template`](docs/templates/opencode.md.template) |
| Shared rules (loaded via `instructions`) | [`rules/`](rules/) |
| Helper scripts (secrets scan, session context, format, tests) | [`scripts/`](scripts/) |
| Config validation | `scripts/validate-opencode-config.sh` |

## Built-in agents

`plan` (DeepSeek V4 Pro) and `build` (DeepSeek V4 Flash) — see `opencode.json`.

## Custom pipeline (summary)

- **`architect`** — planning; invokes `scribe` for `.plan/` artifacts; never executes code.
- **`orchestrate`** — execution coordinator; dispatches `developer`, `frontend-dev`, `ux-dev`, `verifier`, etc.; never writes files directly.
- **`scribe`** — only writer for plans, `docs/changelog|guides|architecture`, root `README`, `.env.example` (per allow list).
- **`review`** — may Task `security-reviewer`, `performance-reviewer`, `doc-reviewer` for focused passes (see agent + skill).

Global **`instructions`** pull in [`rules/`](rules/). Global **`permission`** in `opencode.json` blocks edits to `opencode.json`, lockfiles, `.env*`, and keys.

## Optional workflow skills

[`skills/ship`](skills/ship), [`skills/hotfix`](skills/hotfix), [`skills/debug-fix`](skills/debug-fix), [`skills/tdd`](skills/tdd) — add the skill to an agent’s `permission.skill` when you want that workflow available.

## Desktop / shell environment

If the OpenCode desktop app misses `mise`/`node`/`ruby` on PATH, put shared setup in `~/.zshenv` and optional secrets in `~/.opencode-agent-env` (see RUNBOOK). Run commands through [`scripts/agent-run.zsh`](scripts/agent-run.zsh) for a consistent login shell.
