---
name: worktree-env
description: "Linked git worktree: copy .env and .env.local from main checkout (bash/cp only)"
modelTier: "fast"
roleReminder: "Run scripts/worktree-env.sh once; return its JSON. Do not invent a mega bash -lc script."
---

## Skill reference (optional load)

Load when the parent (`orchestrate`) delegates worktree env setup before preflight. Follow the **worktree-env** agent Hard Rules first.

## Purpose

When the workspace is a **linked git worktree**, ensure repo-root env files (default **`.env`**, **`.env.local`**) are **copies** of the main checkout files so each worktree can customize settings (e.g. a separate database) without affecting other checkouts.

Override the file list with space-separated **`WORKTREE_ENV_FILES`** (e.g. `WORKTREE_ENV_FILES=".env .env.local .env.development"`).

## Hard Rules

1. **Prefer the script:** From the worktree cwd, run **exactly one**:
   ```bash
   bash "${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}/scripts/worktree-env.sh"
   ```
   Return that JSON (or a thin wrapper) to the parent, then **stop**.
2. **Do not** package this procedure into a long `bash -lc '…'` one-liner. That hits `Argument list too long` and wastes turns.
3. **Do not** hand-build JSON in the shell. The script already emits canonical JSON.
4. Do not read or print the contents of env files.
5. Do not modify env files in the main checkout—only create or replace copies **in the current worktree root** (the script does this).
6. Emit exactly one final report to the parent with **canonical evidence**, then stop.

## Fallback (script missing only)

If the script path does not exist, run these **short** commands (never one mega-script):

1. `git rev-parse --is-inside-work-tree` → must be `true`; else `worktree_env: skipped_not_git`.
2. `git_dir=$(git rev-parse --path-format=absolute --git-dir)`. If `git_dir` matches `*/.git/worktrees/*`, treat as linked. Otherwise **skip** with `worktree_env: skipped_not_linked_worktree`.
3. **Main checkout root:**
   - If **`PREFLIGHT_MAIN_REPO_ROOT`** is set: `main_root="${PREFLIGHT_MAIN_REPO_ROOT%/}"`.
   - Else: `common=$(git rev-parse --path-format=absolute --git-common-dir)`; `main_root=$(dirname "$common")`.
4. **Worktree root:** `wt_root=$(git rev-parse --show-toplevel)`.
5. For each basename in `${WORKTREE_ENV_FILES:-.env .env.local}`:
   - Missing source → `skipped_missing_source`.
   - Target is a regular file (`test -f` and not `test -L`) → `ok_existing` (do not overwrite).
   - Target missing or symlink → if symlink, `rm -f "$target"` then `cp "$source" "$target"`; verify `test -f` and `test ! -L`.
6. Build the structured report **in your final message** (not via nested shell quoting).

## Permissions (OpenCode)

- **Prefer `cp` via `bash` only** (no `edit` tool on `.env`). Global `opencode.json` may deny edits to `.env`; many stacks still allow file copy through **bash**—try that first.
- **`external_directory`:** main checkout paths must be **allow** (not `ask`) so `cp` can read sources outside the worktree root without mid-session prompts.
- If `cp` is **denied by the sandbox**, add under **`agents/worktree-env.md`** `permission.edit` with `"*": deny` and `".env": allow` at repo root (mirror `scribe` patterns), then retry—or run the same `cp` command manually in a terminal.

## Output (structured)

Return to parent (script stdout is authoritative):

- `worktree_env`: `ok` | `skipped_not_git` | `skipped_not_linked_worktree` | `failed_cp`
- `wt_root`, `main_root`: absolute paths
- `files`: per-file `{ name, status: ok | ok_existing | skipped_missing_source | failed_cp, source, target, is_regular_file }` (paths only, not contents)
- `commands_run`: brief list (`cp`, `test -f`, `test ! -L`, etc.)
- `recommended_env_fix`: one line if failed
- If `failed_cp`, include `blocker_code: ENV_BLOCKED` only when the user cannot proceed to preflight without fixing this (orchestrate may still run preflight verification after manual fix)

## On success

Status ready for **`preflight`** agent: worktree env copies are in place or not required. Parent should set `worktree_env_checked: true` and store this report as `worktree_env_evidence` — do not expect a second **`worktree-env`** invocation in the same bootstrap unless canonical verification later contradicts this evidence.
