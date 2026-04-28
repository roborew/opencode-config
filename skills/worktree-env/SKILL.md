---
name: worktree-env
description: "Linked git worktree: symlink workspace .env to main checkout .env (bash/ln only)"
modelTier: "fast"
roleReminder: "Only create/replace root .env as a symlink when in a linked worktree; otherwise skip. One report and stop."
---

## Skill reference (optional load)

Load when the parent (`orchestrate`) delegates startup worktree env setup before preflight. Follow the **worktree-env** agent Hard Rules first.

## Purpose

When the workspace is a **linked git worktree**, ensure `<repo-root>/.env` is a **symlink** to the **main checkout’s** `.env` so secrets stay in one place. Use **`bash` + `ln` only** (no edit/write tools for secret contents).

## Hard Rules

1. Do not read or print the contents of `.env` files.
2. Do not modify the main checkout’s `.env`—only create or replace the symlink **in the current worktree root**.
3. If `.env` in the worktree exists as a **regular file** (not a symlink), **stop Blocked**—do not delete or overwrite without user action.
4. Emit exactly one final report to the parent, then stop.

## Detection

Run from **repository root** (`git rev-parse --show-toplevel`); `cd` there first if needed.

1. **Inside git:** `git rev-parse --is-inside-work-tree` → must be `true`; else `worktree_env: skipped_not_git`.
2. **Linked worktree:** `git_dir=$(git rev-parse --path-format=absolute --git-dir)`. If `git_dir` matches `*/.git/worktrees/*`, treat as linked. Otherwise **skip** with `worktree_env: skipped_not_linked_worktree` (primary checkout or unusual layout).
3. **Source `.env` path:**
   - If environment variable **`PREFLIGHT_MAIN_REPO_ROOT`** is set and non-empty: `source_env="${PREFLIGHT_MAIN_REPO_ROOT%/}/.env"`.
   - Else: `common=$(git rev-parse --path-format=absolute --git-common-dir)`; `main_root=$(dirname "$common")"`; `source_env="${main_root}/.env"`. (Assumes common dir is `<repo>/.git`; document in report if `separate-git-dir` breaks this.)
4. **Worktree root:** `wt_root=$(git rev-parse --show-toplevel)`; target `"${wt_root}/.env"`.

## Actions (linked worktree only)

- If **`source_env`** is not a readable path (missing): **Blocked** — `recommended_env_fix`: create `.env` in the main checkout (or set `PREFLIGHT_MAIN_REPO_ROOT` to the directory that contains `.env`).
- If **`target`** exists and is **not** a symlink: **Blocked** — `recommended_env_fix`: move or remove the real file at `.env` in the worktree (after backing up secrets), then re-run this task.
- If **`target`** is missing, or is a symlink with the wrong target: run **`ln -sfn "$source_env" "$target"`** via bash (absolute `source_env` avoids fragile relative links).
- If **`target`** already symlink and resolves to **`source_env`**: pass (no `ln` needed).

Verify with: `test -L "$target"` and compare `readlink` / canonical paths to `source_env` as appropriate for the OS (macOS: `readlink`; GNU `readlink -f` if available).

## Permissions (OpenCode)

- **Prefer `ln` via `bash` only** (no `edit` tool on `.env`). Global `opencode.json` may deny edits to `.env`; many stacks still allow symlink creation through **bash**—try that first.
- If `ln` is **denied by the sandbox**, add under **`agents/worktree-env.md`** `permission.edit` with `"*": deny` and `".env": allow` at repo root (mirror `scribe` patterns), then retry—or run the same `ln` command manually in a terminal.

## Output (structured)

Return to parent:

- `worktree_env`: `ok` | `skipped_not_git` | `skipped_not_linked_worktree` | `blocked_missing_source` | `blocked_regular_file` | `failed_ln`
- `commands_run`: brief list
- `source_env` / `target`: paths (not contents)
- `recommended_env_fix`: one line if Blocked or failed
- If Blocked or `failed_ln`, include `blocker_code: ENV_BLOCKED` only when the user cannot proceed to preflight without fixing this (orchestrate may still run preflight verification after manual fix)

## On success

Status ready for **`developer`** preflight: worktree `.env` symlink is in place or not required.
