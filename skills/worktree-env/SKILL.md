---
name: worktree-env
description: "Linked git worktree: symlink .env and .env.local from main checkout (bash/ln only)"
modelTier: "fast"
roleReminder: "Only create/replace root env files as symlinks when in a linked worktree; otherwise skip. One report and stop."
---

## Skill reference (optional load)

Load when the parent (`orchestrate`) delegates worktree env setup before preflight. Follow the **worktree-env** agent Hard Rules first.

## Purpose

When the workspace is a **linked git worktree**, ensure repo-root env files (default **`.env`**, **`.env.local`**) are **symlinks** to the **main checkout** so secrets stay in one place. Use **`bash` + `ln` only** (no edit/write tools for secret contents).

Override the file list with space-separated **`WORKTREE_ENV_FILES`** (e.g. `WORKTREE_ENV_FILES=".env .env.local .env.development"`).

## Hard Rules

1. Do not read or print the contents of env files.
2. Do not modify env files in the main checkout—only create or replace symlinks **in the current worktree root**.
3. If a target env file in the worktree exists as a **regular file** (not a symlink), **stop Blocked** for that file—do not delete or overwrite without user action.
4. Emit exactly one final report to the parent, then stop.

## Detection

Run from **repository root** (`git rev-parse --show-toplevel`); `cd` there first if needed.

1. **Inside git:** `git rev-parse --is-inside-work-tree` → must be `true`; else `worktree_env: skipped_not_git`.
2. **Linked worktree:** `git_dir=$(git rev-parse --path-format=absolute --git-dir)`. If `git_dir` matches `*/.git/worktrees/*`, treat as linked. Otherwise **skip** with `worktree_env: skipped_not_linked_worktree` (primary checkout or unusual layout).
3. **Main checkout root:**
   - If **`PREFLIGHT_MAIN_REPO_ROOT`** is set and non-empty: `main_root="${PREFLIGHT_MAIN_REPO_ROOT%/}"`.
   - Else: `common=$(git rev-parse --path-format=absolute --git-common-dir)`; `main_root=$(dirname "$common")"`. (Assumes common dir is `<repo>/.git`; document in report if `separate-git-dir` breaks this.)
4. **Worktree root:** `wt_root=$(git rev-parse --show-toplevel)`.
5. **Files to link:** `${WORKTREE_ENV_FILES:-.env .env.local}` (space-separated basenames only).

## Actions (linked worktree only)

For each basename `f` in the file list:

- `source="${main_root}/${f}"`; `target="${wt_root}/${f}"`.
- If **`source`** is not a readable path: **skip** this file (`skipped_missing_source` for `f`); continue other files.
- If **`target`** exists and is **not** a symlink: **Blocked** — `recommended_env_fix`: move or remove the real file at `target` in the worktree (after backing up secrets), then re-run this task.
- If **`target`** is missing, or is a symlink with the wrong target: run **`ln -sfn "$source" "$target"`** via bash (absolute `source` avoids fragile relative links).
- If **`target`** already symlink and resolves to **`source`**: pass for this file (no `ln` needed).

Verify each linked file with: `test -L "$target"` and compare `readlink` / canonical paths to `source` as appropriate for the OS (macOS: `readlink`; GNU `readlink -f` if available).

**Overall status:** `ok` if no file is Blocked; any Blocked file → `worktree_env: blocked_regular_file` or `failed_ln` and stop.

## Permissions (OpenCode)

- **Prefer `ln` via `bash` only** (no `edit` tool on `.env`). Global `opencode.json` may deny edits to `.env`; many stacks still allow symlink creation through **bash**—try that first.
- If `ln` is **denied by the sandbox**, add under **`agents/worktree-env.md`** `permission.edit` with `"*": deny` and `".env": allow` at repo root (mirror `scribe` patterns), then retry—or run the same `ln` command manually in a terminal.

## Output (structured)

Return to parent:

- `worktree_env`: `ok` | `skipped_not_git` | `skipped_not_linked_worktree` | `blocked_regular_file` | `failed_ln`
- `files`: per-file `{ name, status: ok | skipped_missing_source | blocked_regular_file | failed_ln, source, target }` (paths only, not contents)
- `commands_run`: brief list
- `recommended_env_fix`: one line if Blocked or failed
- If Blocked or `failed_ln`, include `blocker_code: ENV_BLOCKED` only when the user cannot proceed to preflight without fixing this (orchestrate may still run preflight verification after manual fix)

## On success

Status ready for **`developer`** preflight: worktree `.env` symlink is in place or not required.
