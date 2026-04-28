---
name: preflight
description: "Environment readiness checks for runtime, toolchain, and test commands"
modelTier: "fast"
roleReminder: "Run minimal checks and produce a concise readiness report. Do not implement code or amend artifacts."
---

## Skill reference (optional load)

Checklist order for environment readiness. Load only when the parent requests preflight. Follow your agent Hard Rules first. `SKILL_LOADED: preflight` is optional.

## Preflight

You run environment readiness checks when requested at startup (or after environment changes). Your output is consumed by developer/orchestrator as a session readiness report.

## Hard Rules
1. Do not implement code or edit files.
2. Do not amend plan artifacts directly.
3. Run only minimal runtime/toolchain checks.
4. Return structured readiness output for parent reporting.

## Checks (run in order)
1. **Project README** — Read the project README (`README.md`, `README`, or similar) for environment setup, prerequisites, or preflight instructions. Incorporate any documented requirements into the checks below.
2. **Worktree `.env` symlink (read-only)** — Only when the repo is a **linked git worktree** (`git rev-parse --path-format=absolute --git-dir` path contains `/.git/worktrees/`):
   - Resolve expected source the same way as **`worktree-env`**: if `PREFLIGHT_MAIN_REPO_ROOT` is set, expect `"${PREFLIGHT_MAIN_REPO_ROOT%/}/.env"`; else `main_root=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")` and expect `"${main_root}/.env"`.
   - At `git rev-parse --show-toplevel`, verify `.env` exists, is a **symlink** (`test -L .env`), and its target matches the expected source path (compare with `readlink` / absolute normalization appropriate to the OS).
   - If any check fails: **Blocked** — `recommended_env_fix`: have orchestrate re-run **`worktree-env`** (or run the `ln -sfn` documented in `skills/worktree-env/SKILL.md` manually), then re-run preflight.
   - If not a linked worktree: **skip** this item; note `worktree_env: skipped_not_linked_worktree` in output.
3. **Runtime versions** — From project files (package.json, Gemfile, etc.), confirm required runtimes exist and report versions:
   - e.g. `node -v`, `ruby -v`, `bundle -v`, `pnpm -v`
4. **Command resolution** — Confirm test/build runner resolves from current shell context.
5. **Smoke check** — Execute a tiny test-command smoke check (or equivalent verification command) if project defines one.
6. **Claude-context indexing** — If `claude-context` MCP is available: call `get_indexing_status` for the workspace path. If not indexed, call `index_codebase` to index the codebase, then verify with `get_indexing_status` until ready. Preflight does not pass until the codebase is indexed (or claude-context is unavailable). If claude-context is not configured, skip this check.

## Output
Produce structured readiness content:
- `Status`: `Ready` or `Blocked`
- `preflight_checks` / `Runtime checks`: exact commands run and their output (or failure details)
- `worktree_env`: `ok` | `skipped_not_linked_worktree` | `skipped_not_git` | `failed` — linked-worktree `.env` symlink verification only (no `ln` here; orchestrate runs **`worktree-env`** before this preflight when the user opts in)
- `claude_context_index`: `indexed` | `skipped` (MCP unavailable) | `failed` — include indexing status or error if applicable
- `stderr summaries`: for any failures
- `Notes`: version manager assumptions, required shell initialization, remediation steps if Blocked

## On Blocked
If any check fails:
- Set `Status: Blocked`
- Include `preflight_checks` with exact failing command + stderr
- Include likely cause (version manager not loaded, wrong runtime, missing toolchain)
- Include one concrete `recommended_env_fix` for the user
