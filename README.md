# OpenCode Agent Orchestration

This repository uses a stage-based orchestration model to keep cheaper models focused and context-light while preserving quality gates.

## Built-in Agents (OpenCode Defaults)

OpenCode's built-in `plan` and `build` remain untouched for generic/quick tasks. Both use the Codex model by default in this config.

- **`plan`** — Built-in primary agent for analysis and planning without edits. Use for quick planning or review.
- **`build`** — Built-in primary agent with full tools. Use for ad-hoc coding or generic development.

## Custom Pipeline (Serious Work)

For serious features, refactors, or multi-stage work, use the custom **Architect → Orchestrator → Subagents** pipeline:

- **Primary planning:** `architect` (default agent) — read-only: exploration, reporting, drafting plans; also owns review and documentation after implementation
- **Primary execution:** `orchestrate` — coordinates execution; never writes directly; prompts user back to architect on completion
- **Planning specialists (architect subagents):** `debugger`, `refactor`, `review`, `designer` — read-only; return plan drafts
- **Documentation generator:** `document` — read-only; generates changelog/guides/architecture content; architect invokes, then scribe writes
- **Artifact writer:** `scribe` — only agent that writes plan artifacts and docs (invoked by architect and orchestrate)
- **Recovery replanner:** `helper`
- **Execution subagents (orchestrate only):** `developer`, `frontend-dev`, `ux-dev` — coding agents; architect never invokes these. `ux-dev` generates HTML-only framework-agnostic prototypes from design briefs into `.prototype/<slug>/`.
- **Operator escalation:** `senior-dev` — orchestrator subagent; invoke when developer is stuck. Diagnose + fix blocker; no preflight. Hand back to orchestrator to resume with developer.
- **Verification gate:** `verifier`
- **Image/layout reviewer:** `vision` — invoked by orchestrate only when the model needs to see the UI (layout, design, visual regression). Not triggered on every test run.
- **Optional mentor:** `mentor`

**Responsibility boundary:** Architect owns planning, review, and documentation. Orchestrator owns execution only. User switches: architect → orchestrate (to execute) → architect (for review + docs).

## How the Custom Pipeline Works

**Phase 1 — Planning**
1. `architect` asks what type of plan is needed (Feature, Debug, Refactor, Review, Document, Prototype Design) when prompt is greeting/unspecified.
2. `architect` drafts content (and invokes specialist subagents when needed). For Prototype Design: architect prompts for design intake (purpose, audience, feel, color scheme, icon set, sections, accessibility, reference assets), enforces HTML-only framework-agnostic prototype output, invokes `designer` for brief synthesis, then scribe writes `.plan/design.<slug>.md`.
3. `architect` invokes `scribe` to write the artifact to `.plan/<type>.<slug>.md` — the scribe step is mandatory.
4. Switch to `orchestrate`.

**Phase 2 — Execution**
5. `orchestrate` starts by asking whether to run startup preflight checks now (`yes/no`).
6. If yes, `orchestrate` invokes `developer` preflight (developer loads `preflight` skill), reports results, and pauses for remediation if blocked.
7. If no (or preflight is ready), `orchestrate` ensures artifact exists (architect already wrote it via scribe). If missing, dispatches `scribe` to create it:
   - `.plan/feature.<slug>.md`
   - `.plan/debug.<slug>.md`
   - `.plan/refactor.<slug>.md`
   - `.plan/review.<slug>.md`
   - `.plan/design.<slug>.md` (prototype design brief)
8. `orchestrate` dispatches one stage at a time to `developer`, `frontend-dev`, or `ux-dev`. Design artifacts (`Owner: ux-dev`) are executed by `ux-dev`, which generates HTML-only prototype code into `.prototype/<slug>/`.
9. Execution subagents return completion reports with evidence.
10. `orchestrate` grades each child report (`PASS` / `NEEDS_RETRY` / `BLOCKED`) before progressing.
11. `verifier` checks acceptance criteria with evidence before completion.
12. If execution is stuck, child output is low quality, verifier fails repeatedly, or environment blocks, `orchestrate` invokes `helper`, then `scribe` updates the existing artifact before retry.
13. When verifier passes for all stages, orchestrate prompts: **"Implementation complete. Switch to architect for review and documentation sign-off."**

**Phase 3 — Review and Documentation (architect)**
14. User switches back to `architect`.
15. `architect` invokes `review` for final sign-off. If remediation needed: `scribe` writes review artifact → user switches to orchestrate to apply fixes → repeat Phase 2.
16. If sign-off: `architect` invokes `document` to generate changelog/guides/architecture content, then `scribe` writes the docs.

## Verifier and Review Responsibilities

- `verifier`: validates requirement conformance against original feature criteria (and review criteria when review is active). Invoked by orchestrate.
- `review`: architect's planning specialist; for post-implementation, assesses completed work and returns sign-off or remediation tasks. Architect invokes; if remediation, scribe writes review artifact and user switches to orchestrate.

If verification fails during execution, orchestrate invokes `helper` and `scribe` updates the review artifact. When architect returns remediation, orchestrate runs developer → verifier again.

## MCP Usage Expectations

Use MCP selectively when it helps resolve uncertainty:

- **`claude-context`**: Semantic code search in workspace. Use during planning to discover files/code to change and populate `FilesToChange` with evidence. Preflight checks ensure the codebase is indexed before planning; if not indexed, preflight runs `index_codebase` and verifies readiness.
- **`context7`**: Up-to-date docs for 9000+ external libraries. Use when framework/library API behavior is uncertain (e.g., React, Next.js, Supabase). Limit to 3 calls per question.
- **`docs-mcp-server`**: Internal docs, prototypes, and linked references.
- **`dash-api`**: API/library contract lookup.

If a request says "look at the prototype", check `docs-mcp-server` first.

## Required Final Docs Per Feature

After architect's review sign-off, `document` generates content and `scribe` writes:

- `docs/changelog/<date>-<slug>.md`
- `docs/guides/<feature-slug>.md`
- `docs/architecture/<feature-slug>.md`

Templates live in:

- `docs/changelog/TEMPLATE.md`
- `docs/guides/TEMPLATE.md`
- `docs/architecture/TEMPLATE.md`
- `docs/prototypes/HTML_PROTOTYPE_TEMPLATE.md` (reference prompt for HTML-only prototype generation)

## Desktop App Shell Environment Fix

If OpenCode CLI works but desktop agents miss tools from `mise`, `conda`, `nvm`, etc., the desktop app is likely launching shells with a different environment than your terminal.

### Required fix (`~/.zshenv` for all zsh modes)

Put shared runtime setup in `~/.zshenv` (loaded by interactive and non-interactive zsh), including `mise` activation and any PATH entries needed by tools:

```sh
export PATH="$HOME/.local/bin:$PATH"
export PATH="/opt/homebrew/bin:$PATH"
export PATH="/usr/local/bin:/usr/local/sbin:$PATH"
export PATH="/opt/homebrew/opt/sqlite/bin:$PATH"
export PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"
export PATH="/opt/homebrew/Caskroom/miniconda/base/condabin:$PATH"

if [ -x "/Users/USERNAME/.local/bin/mise" ]; then
  unset __MISE_ORIG_PATH MISE_SHELL __MISE_WATCH
  eval "$(/Users/USERNAME/.local/bin/mise env -s zsh)"
fi
```

This is the key fix that makes agent shells resolve `ruby`/`node` from mise instead of system defaults.

If you use `brew shellenv` in `~/.zprofile`, re-apply mise after it so login shells keep the same tool PATH:

```sh
# ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
eval "$(/Users/USERNAME/.local/bin/mise env -s zsh)"
```

### Env vars for code tools and agents

If tools need env vars (API keys, toggles, endpoints), load them from a machine-local file in `~/.zshenv`:

```sh
if [ -f "$HOME/.opencode-agent-env" ]; then
  . "$HOME/.opencode-agent-env"
fi
```

Then add exports to `~/.opencode-agent-env`, for example:

```sh
export EXAMPLE_API_KEY="..."
export EXAMPLE_BASE_URL="https://example.com"
```

`~/.opencode-agent-env` is not populated automatically. If a variable is missing in agents, add it there explicitly.

### Force command execution via script (subagent fallback)

If a subagent still behaves inconsistently, execute commands through:

```sh
./.opencode/agent-run.zsh 'which ruby && ruby -v'
```

This wrapper loads `~/.opencode-agent-env`, applies `mise env`, and runs the command in a login zsh.

### `mise` trust warning fix

If agent commands print `mise WARN ... mise.toml are not trusted`, run this in the affected project root:

```sh
mise trust --all
```

Or trust one file directly:

```sh
mise trust /path/to/mise.toml
```

For non-interactive subagents across known work roots, set global trusted paths once:

```sh
mise settings add trusted_config_paths /Users/USERNAME/.config/opencode
mise settings add trusted_config_paths /Users/USERNAME/05_Repos
mise settings get trusted_config_paths
```

Then re-run checks:

```sh
mise trust --show
mise current ruby || true
mise current node || true
which ruby && ruby -v
which node && node -v
```

### PATH and command diagnostics

Run these in `@helper` when something is missing:

```sh
echo "SHELL=$SHELL"
ps -p $$ -o command=
echo "flags=$-"
command -v mise || true
mise --version || true
mise current ruby || true
mise which ruby || true
mise current node || true
mise which node || true
which ruby && ruby -v
which node && node -v
```

Quick multi-command PATH check:

```sh
for cmd in ruby node python pip conda pnpm bun go java; do
  printf "%-8s -> %s\n" "$cmd" "$(command -v "$cmd" || echo MISSING)"
done
```

If `mise current node` is unset, configure it globally or per-project:

```sh
mise use -g node@24.2.0
# or inside a project:
mise use node@24.2.0
```

### Cleanup / rollback

If you previously set a wrapper shell override, remove it:

```sh
launchctl unsetenv SHELL
```
