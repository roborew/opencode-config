# OpenCode Agent Orchestration

This repository uses a stage-based orchestration model to keep cheaper models focused and context-light while preserving quality gates.

## Built-in Agents (OpenCode Defaults)

OpenCode's built-in `plan` and `build` remain untouched for generic/quick tasks. Both use the Codex model by default in this config.

- **`plan`** — Built-in primary agent for analysis and planning without edits. Use for quick planning or review.
- **`build`** — Built-in primary agent with full tools. Use for ad-hoc coding or generic development.

## Custom Pipeline (Serious Work)

For serious features, refactors, or multi-stage work, use the custom **Architect → Orchestrator → Subagents** pipeline:

- **Primary planning:** `architect` (default agent)
- **Primary execution:** `orchestrator`
- **Planning specialists (subagents):** `debugger`, `refactor`, `review`
- **Artifact writer:** `scribe`
- **Recovery replanner:** `helper`
- **Execution subagents:** `implementor`, `designer`
- **Verification gate:** `verifier`
- **Optional mentor:** `mentor`

## How the Custom Pipeline Works

1. `architect` asks what type of plan is needed (Feature, Debug, Refactor, Review) when prompt is greeting/unspecified.
2. `architect` drafts content (and invokes specialist subagents when needed).
3. `architect` invokes `scribe` to write the artifact to `.plan/<type>.<slug>.md` — the scribe step is mandatory.
4. Switch to `orchestrator`.
5. `orchestrator` ensures artifact exists (architect already wrote it via scribe). If missing, dispatches `scribe` to create it:
   - `.plan/feature.<slug>.md`
   - `.plan/debug.<slug>.md`
   - `.plan/refactor.<slug>.md`
   - `.plan/review.<slug>.md`
5. `orchestrator` runs a startup environment preflight via `helper`.
6. `scribe` writes preflight results to artifact `EnvReadiness`.
7. `orchestrator` dispatches one stage at a time to `implementor` or `designer` only when environment is ready.
8. Execution subagents return completion reports with evidence.
9. `orchestrator` grades each child report (`PASS` / `NEEDS_RETRY` / `BLOCKED`) before progressing.
10. `verifier` checks acceptance criteria with evidence before completion.
11. If execution is stuck, child output is low quality, verifier fails repeatedly, or environment blocks, `orchestrator` invokes `helper`, then `scribe` updates the existing artifact before retry.

## Review Decision Gate

After feature completion, ask: **"Start review now?"**

- **Yes:** `review` dispatches `scribe` to produce/update a review artifact, `implementor` applies fixes, `verifier` signs off.
- **No:** keep artifacts and resume in a new session later (better context hygiene).

## Verifier and Review Responsibilities

- `review`: identifies and prioritizes correctness/security/quality issues.
- `verifier`: validates requirement conformance against original feature criteria (and review criteria when review is active).

If verification fails, update the same `review.<slug>.md` artifact with:
- completed tasks marked complete
- new remediation tasks
- dated `IterationNotes`

The update is performed by `scribe` (not by primary agents).

When failures persist, `helper` produces a minimal strategy amendment and `scribe` applies it to the same artifact (`IterationNotes` + task status changes).

## MCP Usage Expectations

Use MCP selectively when it helps resolve uncertainty:

- `docs-mcp-server` for internal docs, prototypes, and linked references.
- `dash-api` for API/library contract lookup.

If a request says "look at the prototype", check `docs-mcp-server` first.

## Required Final Docs Per Feature

Generate after verification passes:

- `docs/changelog/<date>-<slug>.md`
- `docs/guides/<feature-slug>.md`
- `docs/architecture/<feature-slug>.md`

These docs are written via `scribe`.

Templates live in:

- `docs/changelog/TEMPLATE.md`
- `docs/guides/TEMPLATE.md`
- `docs/architecture/TEMPLATE.md`

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
