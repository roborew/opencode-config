---
name: preflight
description: "Environment readiness checks and repair-first bootstrap for runtime, toolchain, and test commands"
modelTier: "fast"
roleReminder: "Repair what you can automatically, verify with canonical evidence, then report Ready or one concrete Blocked fix."
---

## Skill reference (optional load)

Checklist order for environment readiness. Load only when the parent requests preflight. Follow your agent Hard Rules first. `SKILL_LOADED: preflight` is optional.

## Preflight

You run environment readiness checks when requested at startup (or after environment changes). Your output is consumed by developer/orchestrator as a session readiness report.

## Hard Rules
1. Do not implement application code or amend plan artifacts.
2. Do not read or print the contents of env files.
3. You **may** run documented environment setup commands (README-prescribed installs, `mise exec -- …`, `pnpm install`, `bundle install`, etc.) — not app source edits.
4. Run each repair command **at most once** per preflight invocation; re-check the failing step after repair.
5. Return structured readiness output with canonical evidence for worktree env checks.

## Runtime command prefix

When **`.mise.toml`** (or `.tool-versions`) is present at the repo root, prefix version-sensitive commands with **`mise exec --`** so project-pinned runtimes win over bare PATH (e.g. `mise exec -- node -v`, `mise exec -- pnpm install`). Optionally wrap commands in **`~/.config/opencode/scripts/agent-run.zsh '<command>'`** when the agent shell may lack mise on PATH.

## Checks (run in order)
1. **Project README** — Read the project README (`README.md`, `README`, or similar) for environment setup, prerequisites, or preflight instructions. Incorporate any documented requirements into the checks and repair pass below.
2. **Worktree env symlinks (read-only verification)** — Only when the repo is a **linked git worktree** (`git rev-parse --path-format=absolute --git-dir` path contains `/.git/worktrees/`):
   - Resolve `main_root` the same way as **`worktree-env`** (`PREFLIGHT_MAIN_REPO_ROOT` or `dirname` of `git-common-dir`).
   - Set `wt_root=$(git rev-parse --show-toplevel)`.
   - For each basename in `${WORKTREE_ENV_FILES:-.env .env.local}`: if `"${main_root}/${f}"` exists, verify at worktree root that `f` exists, is a **symlink** (`test -L`), and target matches the expected source (compare with `readlink` / absolute normalization appropriate to the OS). If main has no `f`, skip verification for that file.
   - Record **canonical evidence** per file: `{ name, source, target, readlink, is_symlink, status: ok | ok_existing | failed }`.
   - If any required symlink check fails: set `worktree_env: failed` and include evidence. Do **not** run `ln` here — orchestrate runs **`worktree-env`** before this preflight. If parent already has `worktree_env_checked: true`, include the same `wt_root`/`main_root`/file evidence so the parent can detect contradiction vs **`worktree-env`** report.
   - If not a linked worktree: **skip** this item; note `worktree_env: skipped_not_linked_worktree` in output.
3. **Runtime versions** — From project files (package.json, Gemfile, `.mise.toml`, etc.), confirm required runtimes exist and report versions:
   - e.g. `mise exec -- node -v`, `ruby -v`, `bundle -v`, `mise exec -- pnpm -v`
   - If bare PATH version disagrees with `.mise.toml`, note mismatch; prefer **`mise exec --`** for subsequent checks.
4. **Dependencies** — When `package.json` + lockfile exist and `node_modules/` is absent (or README requires install): run **one** documented install (`mise exec -- pnpm install`, `npm ci`, `bundle install`, etc.). Re-check that the package manager resolves.
5. **Command resolution** — Confirm test/build runner resolves from the repaired shell context (prefer `mise exec --` when applicable).
6. **Smoke check** — Execute a tiny test-command smoke check (or equivalent verification command) if the project defines one.
7. **Claude-context indexing** — When `claude-context` MCP tools are available in the host (`get_indexing_status`, `index_codebase`, etc.): call `get_indexing_status` for the workspace path. If not indexed, call `index_codebase`, then re-check until ready. Do **not** report MCP unavailable when those tools are present — report the actual tool error instead. If MCP is genuinely not configured, set `claude_context_index: skipped`. On indexing failure after one retry, set `failed` and include error; parent may continue for non-discovery work per orchestrate policy.

## Repair pass (automatic, once)

When a check in steps 3–7 fails with a **repairable** cause, run **one** repair before marking Blocked:

| Failure | Repair (once) |
|---------|----------------|
| Wrong PATH node vs `.mise.toml` | Use `mise exec --` for all subsequent commands; report both bare and mise versions |
| Missing `node_modules/` | `mise exec -- pnpm install` or README install command |
| Package manager not found | `corepack enable` or README setup step |
| Smoke/test runner missing deps | Re-run install from README, then smoke again |
| Not indexed | `index_codebase`, wait, `get_indexing_status` again |

After repair, re-run only the failing check(s). If repair succeeds, continue the checklist and set `repair_applied: true` in output.

## Output
Produce structured readiness content:
- `Status`: `Ready` or `Blocked`
- `preflight_checks` / `Runtime checks`: exact commands run and their output (or failure details)
- `repair_applied`: true | false — whether an automatic repair ran this invocation
- `worktree_env`: `ok` | `ok_existing` | `skipped_not_linked_worktree` | `skipped_not_git` | `failed` — linked-worktree env symlink verification only (no `ln` here; orchestrate runs **`worktree-env`** before this preflight)
- `worktree_env_evidence`: `{ wt_root, main_root, files: [{ name, source, target, readlink, is_symlink, status }] }` when linked worktree
- `claude_context_index`: `indexed` | `skipped` (MCP unavailable) | `failed` — include indexing status or error if applicable
- `stderr summaries`: for any failures
- `Notes`: version manager assumptions, required shell initialization, remediation steps if Blocked

## On Blocked
If any check fails after the repair pass (or on an unsafe blocker):
- Set `Status: Blocked`
- Include `preflight_checks` with exact failing command + stderr
- Include likely cause (version manager not loaded, wrong runtime, missing toolchain, regular env file in worktree)
- Include **one** concrete `recommended_env_fix` for the parent — no multi-option menus

Unsafe blockers (no further auto-repair): regular `.env` file in worktree (`blocked_regular_file`), runtime/toolchain entirely missing, install command failed after one attempt.
