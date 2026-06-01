# OpenCode Agent Orchestration

Stage-based **Architect → Orchestrate → subagents** pipeline with model routing in [`opencode.json`](opencode.json). **Canonical operational detail:** [`docs/RUNBOOK.md`](docs/RUNBOOK.md). **Feature pipeline:** [`docs/FEATURE-PIPELINE.md`](docs/FEATURE-PIPELINE.md). **Capability matrix:** [`docs/architecture/opencode-capability-matrix.md`](docs/architecture/opencode-capability-matrix.md).

## Setup

1. **Use this directory as your OpenCode config** — Symlink to `~/.config/opencode`, or set `OPENCODE_CONFIG_DIR` to this path so agents, skills, rules, and `opencode.json` load here.
2. **Each application repository** — Run **`setup-skills`** once (via architect when that skill is enabled). Add **`CONTEXT.md`** and **`opencode.md`** from [`docs/templates/opencode.md.template`](docs/templates/opencode.md.template). `setup-skills` can scaffold **`LANGUAGE.md`** when missing.
3. **Project layout** — The parent folder `~/code/APP/` is a **container only** (no git root there). Siblings are typically **`APP-spec`**, **`APP-web`**, **`APP-api`** (replace `APP` with your product slug, e.g. `myapp`). The parent folder name becomes the app slug (lowercased). GitHub remotes may use different casing; setup reads **git remote** from each clone.
4. **Shell bootstrap (once per stack)** — From the project parent (not inside `APP-spec`):

   **`GH_ORG`** is the GitHub **owner** (user login or organization) — the `owner` in `owner/repo`. It is not the app slug.

   ```bash
   export GH_ORG=your-github-login-or-org
   mkdir -p ~/code/myapp && cd ~/code/myapp
   gh repo clone "$GH_ORG/myapp-web"
   gh repo clone "$GH_ORG/myapp-api"
   gh repo clone "$GH_ORG/myapp-spec"   # if the spec repo already exists
   setup-project
   # Stay on your current spec branch: setup-project --keep-branch
   ```

   Re-runs are safe — tooling refresh and re-link only; spec branch is not forced on existing stacks.

5. **OpenCode stack interview** — In **`APP-spec`**, architect → **setup-project** (or front-door option 7) fills `docs/agents/repos.md` and delegates **stack-bootstrap** per implementation repo.

Implementation repos must exist as sibling clones before spec bootstrap can wire them. Deeper walkthrough: [`docs/upgrade-spec/onboarding-supplement.md`](docs/upgrade-spec/onboarding-supplement.md) (if present).

**Repo naming:** Prefer **surface or capability** (`<app>-web`, `<app>-mobile`, `<app>-api`) over vague “frontend” only.

## Daily use

### Product (spec repo)

`grill-me` → `to-prd` → human approves PRD → architect runs fanout (fanout-issues skill)

### Implementation (per repo, dependency order)

1. **`architect`** in impl repo → **option 1** (spec workflow / issue-expand) for `feature:<slug>` — codebase-backed implementation planning on each issue (readable markdown + `opencode-task-yaml` stages).
2. **`orchestrate`** → GitHub backlog `feature:<slug>` (stage-by-stage when expanded).
3. **`architect`** → per-issue / Mode F sign-off → **`ship`** for PR in that repo.
4. When all repos done: **`feature-complete`** in **spec** (closes parent PRD issue, rollup PR links).

**Legacy path:** architect **option 2** (legacy local plan) → `.plan/feature.<slug>.md` → orchestrate.

## Quick reference

| Topic | Location |
|--------|----------|
| Feature pipeline, two modes | [`docs/FEATURE-PIPELINE.md`](docs/FEATURE-PIPELINE.md) |
| Pipeline, grading, MCP policy | [`docs/RUNBOOK.md`](docs/RUNBOOK.md) |
| Per-project context template | [`docs/templates/opencode.md.template`](docs/templates/opencode.md.template) |
| Shared rules (loaded via `instructions`) | [`rules/`](rules/) |
| Helper scripts (secrets scan, session context, format, tests) | [`scripts/`](scripts/) |
| Git / SQL guardrails (scripts) | [`scripts/block-dangerous-git.sh`](scripts/block-dangerous-git.sh), [`scripts/preflight-git.sh`](scripts/preflight-git.sh) |

## Built-in agents

`plan` (DeepSeek V4 Pro) and `build` (DeepSeek V4 Flash) — see `opencode.json`.

## Custom pipeline (summary)

- **`architect`** — planning; invokes `scribe` for `.plan/` artifacts; never executes code.
- **`orchestrate`** — execution coordinator; dispatches `developer`, `frontend-dev`, `ux-dev`, `verifier`, etc.; never writes files directly.
- **`scribe`** — only writer for plans, `docs/changelog|guides|architecture|adr|agents`, `CONTEXT.md`, `CONTEXT-MAP.md`, root `README`, optional `AGENTS.md`, `.env.example` (per allow list in [`agents/scribe.md`](agents/scribe.md)).
- **`review`** — may Task `security-reviewer`, `performance-reviewer`, `doc-reviewer` for focused passes (see agent + skill).

Global **`instructions`** pull in [`rules/`](rules/). Global **`permission`** in `opencode.json` allows workspace edits with asks/denies for `opencode.json`, lockfiles, `.env*`, keys, and credential directories under home.

## Optional workflow skills

[`skills/ship`](skills/ship), [`skills/hotfix`](skills/hotfix), [`skills/debug-fix`](skills/debug-fix), [`skills/tdd`](skills/tdd), [`skills/handoff`](skills/handoff), [`skills/zoom-out`](skills/zoom-out), [`skills/caveman`](skills/caveman), [`skills/to-issues`](skills/to-issues), [`skills/setup-skills`](skills/setup-skills) — add each skill to an agent’s `permission.skill` in [`agents/*.md`](agents/) when you want it available (`opencode.json` does not list skills).

**`grill-me`** (architect Mode A) embeds the [grill-with-docs](https://github.com/mattpocock/skills/tree/main/skills/engineering/grill-with-docs) flow: domain glossary + ADRs persisted via `scribe`.

**Git guardrails:** `opencode.json` in this repo does **not** define PreToolUse hooks (host-dependent). Use `scripts/preflight-git.sh '<command>'` before risky git invocations, or wrap tool calls with `scripts/block-dangerous-git.sh` where your runtime supports stdin JSON hooks.

## Desktop / shell environment

If the OpenCode desktop app misses `mise`/`node`/`ruby` on PATH, put shared setup in `~/.zshenv` and optional secrets in `~/.opencode-agent-env` (see RUNBOOK). Run commands through [`scripts/agent-run.zsh`](scripts/agent-run.zsh) for a consistent login shell.
